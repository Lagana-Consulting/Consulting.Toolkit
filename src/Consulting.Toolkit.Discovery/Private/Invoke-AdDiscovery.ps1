function Invoke-AdDiscovery {
    <#
    .SYNOPSIS
    Collects Active Directory discovery data (pure collector).

    .DESCRIPTION
    Performs live AD data collection and writes structured CSV outputs.
    This function intentionally does NOT:
      - apply thresholds (stale/legacy)
      - generate analysis datasets (AD__Domain__Analysis__*)
      - generate risk flags / assessment summaries
      - generate HTML reports
      - compare environments

    Outputs a timestamped run folder containing:
      - 00_schemas (CSV schema definitions)
      - 10_forest  (forest-level datasets)
      - 20_domains (per-domain datasets)
      - 90_logs    (logs)
      - 99_manifest (run metadata CSVs)

    .PARAMETER Environment
    Logical label for this discovery run (Source/Target/etc.)

    .PARAMETER OutputRoot
    Root folder where the run folder will be created.

    .PARAMETER Prefix
    Optional prefix for run folder name. If omitted, derived from forest root domain.

    .PARAMETER CustomerName
    Optional metadata stored in run info.

    .PARAMETER Server
    Optional specific DC/GC to use for initial forest discovery and domain context.

    .PARAMETER Domain
    Optional domain FQDN(s) to limit per-domain collection to. Forest-level datasets still cover the whole forest.

    .OUTPUTS
    PSCustomObject with:
      RunRoot, LogPath, Environment, ForestName, DomainCount, UserCount, ComputerCount, GroupCount, ExecutionTime,
      Status (Complete/Partial), FailedOperationCount, FailedOperations, ExecutionStatusPath
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Environment = "Source",

        [Parameter()]
        [string]$OutputRoot = "c:\scripts\Reports",

        [Parameter()]
        [string]$Prefix = "",

        [Parameter()]
        [string]$CustomerName = "",

        [Parameter()]
        [string]$Server,

        [string[]]$Domain,

        [switch]$IncludeSecurity,

        [Parameter(DontShow)]
        $LogContext
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $Now = Get-Date
    $EnvironmentSafeTag = $Environment.ToLower().Replace(' ', '_')

    $adDiscoveryLogContext = $LogContext
    if (-not $adDiscoveryLogContext) {
        $adDiscoveryLogContext = New-AdDiscoveryDiagnostics -OutputRoot $OutputRoot
    }
    $executionLog = $adDiscoveryLogContext.Events
    $adDiscoveryLogContext.Server = $Server
    function Log-ExecutionStatus {
        param([string]$Operation, [string]$Status, [string]$Message = '',
            [System.Management.Automation.ErrorRecord]$ErrorRecord)
        Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation $Operation -Status $Status -Message $Message -ErrorRecord $ErrorRecord
        if ($Message) {
            Write-Host "    [$Status] $Operation : $Message" -ForegroundColor $(if ($Status -in @('OK', 'EMPTY')) { 'Green' } else { 'Yellow' })
        }
    }

    function Try-Export {
        param([scriptblock]$Action, [string]$Operation)
        Log-ExecutionStatus $Operation 'START'
        try {
            & $Action
            Log-ExecutionStatus $Operation 'OK'
        } catch {
            $status = if ($_.Exception.Data['DiscoveryStatus'] -eq 'SKIP') { 'SKIP' } else { 'FAIL' }
            Log-ExecutionStatus $Operation $status $_.Exception.Message -ErrorRecord $_
        }
    }

    # Verify required functions are available
    foreach ($fn in @('Export-AdCsvSafe', 'Export-AdSchemas', 'Get-AdAdForest', 'Get-AdAdDomains', 'Get-AdAdDomainContext', 'New-AdRunLayout')) {
        if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
            throw "$fn not found. Ensure Consulting.Toolkit.Discovery is properly loaded."
        }
    }

    function Get-DomainScopeTag([string]$DomainFqdn) {
        return ("Domain-{0}" -f $DomainFqdn)
    }

    # -------------------------
    # Forest discovery
    # -------------------------
    Write-Host "Discovering Active Directory forest..." -ForegroundColor Cyan
    $forestParams = @{}
    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $forestParams['Server'] = $Server
        Write-Host "  Using server: $Server" -ForegroundColor Yellow
    }

    Log-ExecutionStatus "Forest Discovery" 'START'
    try {
        $forest = Get-AdAdForest @forestParams
        $domains = @(Get-AdAdDomains -Forest $forest)
        $suffixSet = Get-AdKnownUpnSuffixes -Forest $forest -Domains $domains -AsHashSet
        $allForestDomains = $domains
        if ($Domain) {
            $wanted = @($Domain | ForEach-Object { $_.Trim().ToLowerInvariant() })
            $missing = @($wanted | Where-Object { $_ -notin $domains })
            if ($missing.Count -gt 0) { throw "Domain(s) not found in forest: $($missing -join ', ')" }
            $domains = @($domains | Where-Object { $_ -in $wanted })
            if (-not $domains) { throw "Domain(s) not found in forest: $($Domain -join ', ')" }
        }
        Log-ExecutionStatus "Forest Discovery" "OK"
    } catch {
        Log-ExecutionStatus "Forest Discovery" "FAIL" $_.Exception.Message -ErrorRecord $_
        throw
    }

    Write-Host "  Forest: $($forest.Name)" -ForegroundColor Green
    Write-Host "  Domains: $(@($domains).Count)" -ForegroundColor Green
    $forestQueryServer = if ($Server) { $Server } else { [string]$forest.RootDomain }

    # Default prefix from forest root domain if Prefix not supplied
    $rootDomainTag = if ([string]::IsNullOrWhiteSpace($forest.RootDomain)) { 'UnknownDomain' } else { $forest.RootDomain.ToLower().Replace(' ', '_') }
    $basePrefix = if ($PSBoundParameters.ContainsKey('Prefix') -and -not [string]::IsNullOrWhiteSpace($Prefix)) {
        $Prefix
    } else {
        "AD_{0}" -f $rootDomainTag
    }

    # Environment-tagged prefix
    $EnvironmentPrefix = if ($EnvironmentSafeTag -eq "source") { $basePrefix } else { "${basePrefix}__${EnvironmentSafeTag}" }

    # -------------------------
    # Run layout + folders
    # -------------------------
    $layoutRaw = @(New-AdRunLayout -OutputRoot $OutputRoot -Prefix $EnvironmentPrefix -CreateLog)
    $layout = $layoutRaw |
    Where-Object { $_ -and $_.PSObject -and ($_.PSObject.Properties.Name -contains 'RunRoot') } |
    Select-Object -Last 1

    if (-not $layout) {
        $returnedTypes = ($layoutRaw | ForEach-Object { $_.GetType().FullName } | Sort-Object -Unique) -join ', '
        throw "New-AdRunLayout did not return a layout object with RunRoot. Returned types: $returnedTypes"
    }

    Write-Host "  Output: $($layout.RunRoot)" -ForegroundColor Yellow

    $schemasDir = Join-Path $layout.RunRoot '00_schemas'
    $forestDir = Join-Path $layout.RunRoot '10_forest'
    $domainsRoot = Join-Path $layout.RunRoot '20_domains'
    $manifestDir = Join-Path $layout.RunRoot '99_manifest'
    $logsDir = Join-Path $layout.RunRoot '90_logs'

    foreach ($p in @($schemasDir, $forestDir, $domainsRoot, $manifestDir, $logsDir)) {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }

    if ($adDiscoveryLogContext.LogPath -ne $layout.LogPath) {
        Move-Item -LiteralPath $adDiscoveryLogContext.LogPath -Destination $layout.LogPath -Force -ErrorAction Stop
        $adDiscoveryLogContext.LogPath = $layout.LogPath
    }
    $eventsPath = Join-Path $logsDir ("discovery-{0}.jsonl" -f $adDiscoveryLogContext.RunId)
    if ($adDiscoveryLogContext.EventsPath -ne $eventsPath) {
        Move-Item -LiteralPath $adDiscoveryLogContext.EventsPath -Destination $eventsPath -Force -ErrorAction Stop
        $adDiscoveryLogContext.EventsPath = $eventsPath
    }
    Write-AdDiscoveryEvent -Context $adDiscoveryLogContext -Kind Run -Operation 'Run Layout' -Status OK -Message $layout.RunRoot

    if ($IncludeSecurity) {
        Write-Host "Exporting security datasets (forest)..." -ForegroundColor Cyan
        # Inline: Forest-level (ADCS) security exports
        if ($forestDir -and (Test-Path -LiteralPath $forestDir)) {
            Try-Export -Operation "ADCS Enterprise CAs (forest)" -Action {
                $cas = @(Get-AdSecurityAdcsInventory -Forest $forest -Server $forestQueryServer -Mode EnterpriseCAs)
                $out = Join-Path $forestDir "AD__Forest__Security__ADCS__EnterpriseCAs__Forest.csv"
                $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                if ([string]::IsNullOrWhiteSpace($schemaName)) {
                    $cas | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                } else {
                    $cas | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                }
            }

            Try-Export -Operation "ADCS Enrollment Services Templates (forest)" -Action {
                $map = @(Get-AdSecurityAdcsInventory -Forest $forest -Server $forestQueryServer -Mode EnrollmentServicesTemplates)
                $out = Join-Path $forestDir "AD__Forest__Security__ADCS__EnrollmentServicesTemplates__Forest.csv"
                $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                if ([string]::IsNullOrWhiteSpace($schemaName)) {
                    $map | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                } else {
                    $map | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                }
            }

            Try-Export -Operation "ADCS Certificate Templates (forest)" -Action {
                $templates = @(Get-AdSecurityCertificateTemplates -Forest $forest -Server $forestQueryServer -Mode Templates)
                $out = Join-Path $forestDir "AD__Forest__Security__ADCS__CertificateTemplates__Forest.csv"
                $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                if ([string]::IsNullOrWhiteSpace($schemaName)) {
                    $templates | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                } else {
                    $templates | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                }
            }

            Try-Export -Operation "ADCS Certificate Template Permissions (forest)" -Action {
                $perms = @(Get-AdSecurityCertificateTemplates -Forest $forest -Server $forestQueryServer -Mode TemplatePermissions)
                $out = Join-Path $forestDir "AD__Forest__Security__ADCS__CertificateTemplatePermissions__Forest.csv"
                $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                if ([string]::IsNullOrWhiteSpace($schemaName)) {
                    $perms | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                } else {
                    $perms | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                }
            }
        }
    }

    # -------------------------
    # Schemas
    # -------------------------
    Write-Host "`nExporting CSV schemas..." -ForegroundColor Cyan
    Log-ExecutionStatus "CSV Schemas Export" 'START'
    try {
        Export-AdSchemas -SchemasDir $schemasDir | Out-Null
        Log-ExecutionStatus "CSV Schemas Export" "OK"
    } catch {
        Log-ExecutionStatus "CSV Schemas Export" "FAIL" $_.Exception.Message -ErrorRecord $_
    }

    # -------------------------
    # Forest exports (collector)
    # -------------------------
    Write-Host "Exporting forest-level data..." -ForegroundColor Cyan

    Try-Export -Operation "Forest Summary" -Action {
        (Get-AdAdForestSummary -Forest $forest) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Summary__Forest.csv') -Force -AllowEmpty
    }
    Try-Export -Operation "Forest UPN Suffixes" -Action {
        (Get-AdAdForestUpnSuffixes -Forest $forest -Domains $allForestDomains) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Identity__UpnSuffixes__Forest.csv') -Force -AllowEmpty
    }
    Try-Export -Operation "Replication Sites" -Action {
        (Get-AdAdReplicationSites -Server $forestQueryServer) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__Sites__Forest.csv') -Force -AllowEmpty
    }

    Try-Export -Operation "Replication Subnets" -Action {
        (Get-AdAdReplicationSubnets -Server $forestQueryServer)   | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__Subnets__Forest.csv')   -Force -AllowEmpty
    }
    Try-Export -Operation "Replication SiteLinks" -Action {
        (Get-AdAdReplicationSiteLinks -Server $forestQueryServer) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__SiteLinks__Forest.csv') -Force -AllowEmpty
    }
    Try-Export -Operation "Forest Trusts" -Action {
        (Get-AdAdForestTrusts -ForestName $forest.Name -Server $forestQueryServer -LogPath $layout.LogPath) | Export-AdCsvSafeWithSchema -Path (Join-Path $forestDir 'AD__Forest__Security__Trusts__Forest.csv') -Force -AllowEmpty
    }

    # -------------------------
    # Domain loop (collector)
    # -------------------------
    $allUsers = @()
    $allComputers = @()
    $allGroups = @()

    foreach ($d in $domains) {
        Write-Host "`nProcessing domain: $d" -ForegroundColor Cyan
        $adDiscoveryLogContext.Domain = $d
        $adDiscoveryLogContext.Server = $Server
        Log-ExecutionStatus "Domain Processing ($d)" 'START'
        $domainFailureCountBefore = @($executionLog | Where-Object { $_.Status -eq 'FAIL' }).Count

        try {
            $ctxParams = @{ DomainFqdn = $d; LogPath = $layout.LogPath }
            if (-not [string]::IsNullOrWhiteSpace($Server)) { $ctxParams['Server'] = $Server }
            Write-AdDiscoveryEvent -Kind Query -Operation 'Domain Context' -Status START
            $ctx = Get-AdAdDomainContext @ctxParams
            $adDiscoveryLogContext.Server = $ctx.Server
            Write-AdDiscoveryEvent -Kind Query -Operation 'Domain Context' -Status OK -Message 'Domain context selected.'

            $scopeTag = Get-DomainScopeTag $ctx.DomainFqdn
            $domainDir = Join-Path $domainsRoot $scopeTag
            if (-not (Test-Path -LiteralPath $domainDir)) { New-Item -ItemType Directory -Path $domainDir -Force | Out-Null }

            if ($IncludeSecurity) {
                Write-Host "  - Security discovery (tier0/delegation/adcs signals)" -ForegroundColor Gray
                # Inline: Domain-level security exports
                if ($domainDir -and (Test-Path -LiteralPath $domainDir)) {
                    Try-Export -Operation "Tier0 inventory ($d)" -Action {
                        $tier0 = Get-AdSecurityTier0Inventory -DomainContext $ctx
                        $out1 = Join-Path $domainDir ("AD__Domain__Security__PrivilegedGroupMembers__{0}.csv" -f $scopeTag)
                        $schemaName1 = Resolve-AdSchemaNameForCsv -Path $out1
                        if ([string]::IsNullOrWhiteSpace($schemaName1)) {
                            $tier0.PrivilegedGroupMembers | Export-AdCsvSafe -Path $out1 -Force -AllowEmpty
                        } else {
                            $tier0.PrivilegedGroupMembers | Export-AdCsvSafe -Path $out1 -SchemaName $schemaName1 -Force -AllowEmpty
                        }

                        $out2 = Join-Path $domainDir ("AD__Domain__Security__AdminCountObjects__{0}.csv" -f $scopeTag)
                        $schemaName2 = Resolve-AdSchemaNameForCsv -Path $out2
                        if ([string]::IsNullOrWhiteSpace($schemaName2)) {
                            $tier0.AdminCountObjects | Export-AdCsvSafe -Path $out2 -Force -AllowEmpty
                        } else {
                            $tier0.AdminCountObjects | Export-AdCsvSafe -Path $out2 -SchemaName $schemaName2 -Force -AllowEmpty
                        }

                        $out3 = Join-Path $domainDir ("AD__Domain__Security__ProtectedUsers__{0}.csv" -f $scopeTag)
                        $schemaName3 = Resolve-AdSchemaNameForCsv -Path $out3
                        if ([string]::IsNullOrWhiteSpace($schemaName3)) {
                            $tier0.ProtectedUsers | Export-AdCsvSafe -Path $out3 -Force -AllowEmpty
                        } else {
                            $tier0.ProtectedUsers | Export-AdCsvSafe -Path $out3 -SchemaName $schemaName3 -Force -AllowEmpty
                        }
                    }

                    Try-Export -Operation "AdminSDHolder impact ($d)" -Action {
                        $adminSd = @(Get-AdAdminSdHolderImpact -DomainContext $ctx)
                        $out = Join-Path $domainDir ("AD__Domain__Security__AdminSdHolderImpact__{0}.csv" -f $scopeTag)
                        $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                        if ([string]::IsNullOrWhiteSpace($schemaName)) {
                            $adminSd | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                        } else {
                            $adminSd | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                        }
                    }

                    Try-Export -Operation "Delegation inventory ($d)" -Action {
                        $del = Get-AdSecurityDelegationInventory -DomainContext $ctx

                        $outU = Join-Path $domainDir ("AD__Domain__Security__DelegationUnconstrained__{0}.csv" -f $scopeTag)
                        $schemaNameU = Resolve-AdSchemaNameForCsv -Path $outU
                        if ([string]::IsNullOrWhiteSpace($schemaNameU)) {
                            $del.Unconstrained | Export-AdCsvSafe -Path $outU -Force -AllowEmpty
                        } else {
                            $del.Unconstrained | Export-AdCsvSafe -Path $outU -SchemaName $schemaNameU -Force -AllowEmpty
                        }

                        $outC = Join-Path $domainDir ("AD__Domain__Security__DelegationConstrained__{0}.csv" -f $scopeTag)
                        $schemaNameC = Resolve-AdSchemaNameForCsv -Path $outC
                        if ([string]::IsNullOrWhiteSpace($schemaNameC)) {
                            $del.Constrained | Export-AdCsvSafe -Path $outC -Force -AllowEmpty
                        } else {
                            $del.Constrained | Export-AdCsvSafe -Path $outC -SchemaName $schemaNameC -Force -AllowEmpty
                        }

                        $outP = Join-Path $domainDir ("AD__Domain__Security__DelegationProtocolTransition__{0}.csv" -f $scopeTag)
                        $schemaNameP = Resolve-AdSchemaNameForCsv -Path $outP
                        if ([string]::IsNullOrWhiteSpace($schemaNameP)) {
                            $del.ProtocolTransition | Export-AdCsvSafe -Path $outP -Force -AllowEmpty
                        } else {
                            $del.ProtocolTransition | Export-AdCsvSafe -Path $outP -SchemaName $schemaNameP -Force -AllowEmpty
                        }

                        $outR = Join-Path $domainDir ("AD__Domain__Security__DelegationRBCD__{0}.csv" -f $scopeTag)
                        $schemaNameR = Resolve-AdSchemaNameForCsv -Path $outR
                        if ([string]::IsNullOrWhiteSpace($schemaNameR)) {
                            $del.RBCD | Export-AdCsvSafe -Path $outR -Force -AllowEmpty
                        } else {
                            $del.RBCD | Export-AdCsvSafe -Path $outR -SchemaName $schemaNameR -Force -AllowEmpty
                        }
                    }

                    Try-Export -Operation "SPN Accounts inventory ($d)" -Action {
                        $spn = @(Get-AdSecuritySpnAccounts -DomainContext $ctx)
                        $out = Join-Path $domainDir ("AD__Domain__Security__SpnAccounts__{0}.csv" -f $scopeTag)
                        $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                        if ([string]::IsNullOrWhiteSpace($schemaName)) {
                            $spn | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                        } else {
                            $spn | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                        }
                    }

                    Try-Export -Operation "Domain Controller security signals ($d, best effort)" -Action {
                        $signals = @(Get-AdSecurityDomainControllerSignals -DomainContext $ctx)
                        $out = Join-Path $domainDir ("AD__Domain__Security__DomainControllerSecuritySignals__{0}.csv" -f $scopeTag)
                        $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                        if ([string]::IsNullOrWhiteSpace($schemaName)) {
                            $signals | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                        } else {
                            $signals | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                        }
                    }
                }
            }

            # Domain summary / infrastructure
            Write-Host "  - Domain summary and infrastructure" -ForegroundColor Gray
            Try-Export -Operation "Domain Summary ($d)" -Action {
                (Get-AdAdDomainSummary -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Summary__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "Domain Controllers ($d)" -Action {
                (Get-AdAdDomainControllers -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Infrastructure__DomainControllers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            # Password policies (collector: raw policy datasets)
            Write-Host "  - Password policies" -ForegroundColor Gray
            Try-Export -Operation "Default Password Policy ($d)" -Action {
                (Get-AdAdDefaultPasswordPolicy -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyDefault__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "Fine-grained Password Policies ($d)" -Action {
                (Get-AdAdFineGrainedPasswordPolicies -DomainContext $ctx -LogPath $layout.LogPath) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyFgpp__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "Fine-grained Password Policy Assignments ($d)" -Action {
                (Get-AdAdFineGrainedPasswordPolicyAssignments -DomainContext $ctx -LogPath $layout.LogPath) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyFgppAssignments__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            # Structure / delegation (collector)
            Write-Host "  - Organizational units and delegation" -ForegroundColor Gray
            Try-Export -Operation "Organizational Units ($d)" -Action {
                (Get-AdAdOrganizationalUnits -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Structure__OrganizationalUnits__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "OU Delegation ACLs ($d)" -Action {
                (Get-AdAdOuDelegationAcls -DomainContext $ctx -Scope OneLevel) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__OuDelegationAcls__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            # Identity objects (collector: full sets)
            Write-Host "  - Identity objects (users, groups, computers)" -ForegroundColor Gray
            # Keep collection state local to this domain; failed collections must not
            # produce empty detail datasets or reuse rows from the previous domain.
            $groups = @()
            $users = @()
            $comps = @()
            $usersCollected = $false
            $computersCollected = $false

            Log-ExecutionStatus "Groups ($d)" 'START'
            try {
                $groups = @(Get-AdAdGroups -DomainContext $ctx)
                $allGroups += $groups
                $groups | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Groups__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                Log-ExecutionStatus "Groups ($d)" 'OK'
            } catch {
                Log-ExecutionStatus "Groups ($d)" 'FAIL' $_.Exception.Message -ErrorRecord $_
            }

            Log-ExecutionStatus "Users ($d)" 'START'
            try {
                $users = @(Get-AdAdUsers -DomainContext $ctx -Now $Now -KnownUpnSuffixSet $suffixSet)
                $usersCollected = $true
                $allUsers += $users
                $users | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Users__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                Log-ExecutionStatus "Users ($d)" 'OK'
            } catch {
                Log-ExecutionStatus "Users ($d)" 'FAIL' $_.Exception.Message -ErrorRecord $_
            }

            Log-ExecutionStatus "Computers ($d)" 'START'
            try {
                $comps = @(Get-AdAdComputers -DomainContext $ctx -Now $Now)
                $computersCollected = $true
                $allComputers += $comps
                $comps | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ComputersAll__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                Log-ExecutionStatus "Computers ($d)" 'OK'
            } catch {
                Log-ExecutionStatus "Computers ($d)" 'FAIL' $_.Exception.Message -ErrorRecord $_
            }

            if ($computersCollected) {
                Log-ExecutionStatus "Computer Status Details ($d)" 'START'
                try {
                    Write-Host "  - Computer status details" -ForegroundColor Gray
                    $computerStatus = Get-AdComputerStatusDetails -Computers $comps

                    $inactiveWorkstationsOut = Join-Path $domainDir ("AD__Domain__Identity__ComputersInactiveWorkstations__{0}.csv" -f $scopeTag)
                    $inactiveServersOut = Join-Path $domainDir ("AD__Domain__Identity__ComputersInactiveServers__{0}.csv" -f $scopeTag)

                    $computerStatus.InactiveWorkstations |
                    Export-AdCsvSafe -Path $inactiveWorkstationsOut -SchemaName 'ComputerStatus_InactiveWorkstations' -Force -AllowEmpty

                    $computerStatus.InactiveServers |
                    Export-AdCsvSafe -Path $inactiveServersOut -SchemaName 'ComputerStatus_InactiveServers' -Force -AllowEmpty
                    Log-ExecutionStatus "Computer Status Details ($d)" 'OK'
                } catch {
                    Log-ExecutionStatus "Computer Status Details ($d)" "FAIL" $_.Exception.Message -ErrorRecord $_
                }
            } else {
                Log-ExecutionStatus "Computer Status Details ($d)" 'SKIP' 'Computer collection failed; dependent exports were not attempted.'
            }

            if ($usersCollected) {
                Log-ExecutionStatus "User Status Details ($d)" 'START'
                try {
                    Write-Host "  - User status details" -ForegroundColor Gray
                    $userStatus = Get-AdUserStatusDetails -Users $users

                    $disabledUsersOut = Join-Path $domainDir ("AD__Domain__Identity__UsersDisabled__{0}.csv" -f $scopeTag)
                    $inactiveUsersOut = Join-Path $domainDir ("AD__Domain__Identity__UsersInactive__{0}.csv" -f $scopeTag)

                    $userStatus.DisabledUsers |
                    Export-AdCsvSafe -Path $disabledUsersOut -SchemaName 'UserStatus_DisabledUsers' -Force -AllowEmpty

                    $userStatus.InactiveUsers |
                    Export-AdCsvSafe -Path $inactiveUsersOut -SchemaName 'UserStatus_InactiveUsers' -Force -AllowEmpty
                    Log-ExecutionStatus "User Status Details ($d)" 'OK'
                } catch {
                    Log-ExecutionStatus "User Status Details ($d)" "FAIL" $_.Exception.Message -ErrorRecord $_
                }
            } else {
                Log-ExecutionStatus "User Status Details ($d)" 'SKIP' 'User collection failed; dependent exports were not attempted.'
            }

            Log-ExecutionStatus "Group Membership Details ($d)" 'START'
            try {
                Write-Host "  - Group membership details" -ForegroundColor Gray
                $groupDetails = Get-AdGroupMembershipDetails -DomainContext $ctx

                $emptyGroupsOut = Join-Path $domainDir ("AD__Domain__Identity__GroupsEmpty__{0}.csv" -f $scopeTag)
                $singleMemberGroupsOut = Join-Path $domainDir ("AD__Domain__Identity__GroupsSingleMember__{0}.csv" -f $scopeTag)
                $groupsDisabledInactiveOut = Join-Path $domainDir ("AD__Domain__Identity__GroupsWithDisabledOrInactiveMembers__{0}.csv" -f $scopeTag)

                $groupDetails.EmptyGroups |
                Export-AdCsvSafe -Path $emptyGroupsOut -SchemaName 'GroupMembership_EmptyGroups' -Force -AllowEmpty

                $groupDetails.SingleMemberGroups |
                Export-AdCsvSafe -Path $singleMemberGroupsOut -SchemaName 'GroupMembership_SingleMemberGroups' -Force -AllowEmpty

                $groupDetails.GroupsWithDisabledOrInactiveMembers |
                Export-AdCsvSafe -Path $groupsDisabledInactiveOut -SchemaName 'GroupMembership_DisabledOrInactiveMembers' -Force -AllowEmpty
                Log-ExecutionStatus "Group Membership Details ($d)" 'OK'
            } catch {
                Log-ExecutionStatus "Group Membership Details ($d)" "FAIL" $_.Exception.Message -ErrorRecord $_
            }

            # Published resources (collector)
            Write-Host "  - Published resources" -ForegroundColor Gray
            Try-Export -Operation "Published Printers ($d)" -Action {
                (Get-AdAdPublishedPrinters -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Inventory__PublishedPrinters__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "Published Shared Folders ($d)" -Action {
                (Get-AdAdPublishedSharedFolders -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Inventory__PublishedSharedFolders__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            # Contacts (collector) — use function signature you currently have
            Write-Host "  - AD Contacts" -ForegroundColor Gray
            Try-Export -Operation "Contacts ($d)" -Action {
                (Get-AdAdContacts -DomainName $ctx.DomainFqdn -Server $ctx.DomainController) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Contacts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            # SPNs (collector)
            Write-Host "  - Service Principal Names" -ForegroundColor Gray
            Try-Export -Operation "SPNs ($d)" -Action {
                (Get-AdAdSpns -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Spns__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            # Security inventory (collector: raw facts, no scoring)
            Write-Host "  - Security inventory (SID history, privileged accounts, service candidates)" -ForegroundColor Gray
            Try-Export -Operation "Users SID History ($d)" -Action {
                (Get-AdUsersSidHistory -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__UsersSidHistory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "Service Account Candidates ($d)" -Action {
                (Get-AdServiceAccountCandidates -DomainContext $ctx -Now $Now) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ServiceAccountCandidates__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "Privileged Accounts ($d)" -Action {
                (Get-AdPrivilegedAccounts -DomainContext $ctx) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PrivilegedAccounts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            if ($IncludeSecurity) {
                # -------------------------
                # Phase 1 Security exports (raw facts only)
                # -------------------------
                Write-Host "  - Security (Phase 1: account/kerberos/gpo raw facts)" -ForegroundColor DarkGray

                Try-Export -Operation "Recently Created Objects ($d)" -Action {
                    (Get-AdRecentlyCreatedObjects -DomainContext $ctx -Days 10 -IncludeGpo -LogPath $layout.LogPath) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__RecentlyCreatedObjects__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                }

                Try-Export -Operation "Built-in Administrator Signals ($d)" -Action {
                    (Get-AdBuiltInAdministratorSignals -DomainContext $ctx) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__BuiltInAdministratorSignals__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                }

                Try-Export -Operation "AS-REP Roastable Users ($d)" -Action {
                    (Get-AdAsrepRoastableUsers -DomainContext $ctx) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__AsrepRoastableUsers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                }

                Try-Export -Operation "Privileged Password Age ($d)" -Action {
                    (Get-AdPrivilegedPasswordAge -DomainContext $ctx) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__PrivilegedPasswordAge__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                }

                Try-Export -Operation "GPO Delegation ($d)" -Action {
                    $gpoDelegation = @(Get-AdGpoDelegation -DomainContext $ctx -LogPath $layout.LogPath)
                    $gpoDelegation |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__GPO__Delegation__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                }
            }

            # GPO inventory + links (collector)
            Write-Host "  - Group Policy Objects" -ForegroundColor Gray
            Try-Export -Operation "GPO Inventory ($d)" -Action {
                $gpos = @(Get-AdGpoInventory -DomainContext $ctx -LogPath $layout.LogPath)
                $gpos | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Inventory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            Try-Export -Operation "GPO Links ($d)" -Action {
                (Get-AdGpoLinks -DomainContext $ctx -Scope Subtree -LogPath $layout.LogPath) |
                Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Links__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            }

            $domainFailureCountAfter = @($executionLog | Where-Object { $_.Status -eq 'FAIL' }).Count
            if ($domainFailureCountAfter -gt $domainFailureCountBefore) {
                Log-ExecutionStatus "Domain Processing ($d)" 'PARTIAL' 'One or more datasets failed; see execution status for details.'
            } else {
                Log-ExecutionStatus "Domain Processing ($d)" 'OK'
            }
        } catch {
            Log-ExecutionStatus "Domain Processing ($d)" "FAIL" $_.Exception.Message -ErrorRecord $_
            Write-Host "  Skipping domain due to error: $_" -ForegroundColor Red
            continue
        }
    }

    $adDiscoveryLogContext.Domain = ''
    $adDiscoveryLogContext.Server = ''

    # -------------------------
    # Manifest (collector metadata only)
    # -------------------------
    Write-Host "`nCreating run manifest..." -ForegroundColor Cyan

    Log-ExecutionStatus "Run Manifest" 'START'
    try {
        $allCsv = Get-ChildItem -LiteralPath $layout.RunRoot -Recurse -File -Filter *.csv -ErrorAction Stop
        $manifest = foreach ($f in $allCsv) {
            [pscustomobject]@{
                FileName      = $f.Name
                RelativePath  = $f.FullName.Substring($layout.RunRoot.Length).TrimStart('\', '/')
                Bytes         = $f.Length
                LastWriteTime = $f.LastWriteTime
            }
        }

        $manifestInfo = [pscustomobject]@{
            Environment   = $Environment
            ExecutionTime = $Now
            OutputRoot    = $layout.RunRoot
            Prefix        = $EnvironmentPrefix
            CustomerName  = $CustomerName
            ForestName    = $forest.Name
            DomainCount   = $domains.Count
        }

        @($manifest) | Export-AdCsvSafe -Path (Join-Path $manifestDir 'Run__Manifest__Run.csv') -Force -AllowEmpty
        $manifestInfo | Export-AdCsvSafe -Path (Join-Path $manifestDir 'Run__Info__Run.csv') -Force -AllowEmpty

        Log-ExecutionStatus "Run Manifest" "OK"
    } catch {
        Log-ExecutionStatus "Run Manifest" "FAIL" $_.Exception.Message -ErrorRecord $_
    }

    Write-AdDiscoveryEvent -Kind Run -Operation 'Loaded Modules' -Status INFO -Details @(
        Get-Module ActiveDirectory, GroupPolicy, Consulting.Toolkit.Discovery | Select-Object Name, @{ Name = 'Version'; Expression = { $_.Version.ToString() } }
    )
    $executionStatusPath = Join-Path $manifestDir 'Run__ExecutionStatus__Run.csv'
    Save-AdDiscoveryExecutionStatus -Context $adDiscoveryLogContext -Path $executionStatusPath
    $executionStatusPath = $adDiscoveryLogContext.ExecutionStatusPath
    $outcome = Get-AdDiscoveryOutcome -Context $adDiscoveryLogContext
    $failedOperations = $outcome.FailedOperations
    $status = $outcome.Status

    # -------------------------
    # Completion summary
    # -------------------------
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    if ($status -eq 'Partial') {
        Write-Host "Discovery Partial: $Environment Environment ($($failedOperations.Count) failed operation(s))" -ForegroundColor Yellow
    } else {
        Write-Host "Discovery Complete: $Environment Environment" -ForegroundColor Green
    }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Forest: $($forest.Name)" -ForegroundColor Yellow
    Write-Host "Domains: $($domains.Count)" -ForegroundColor Yellow
    Write-Host "Users: $($allUsers.Count)" -ForegroundColor Yellow
    Write-Host "Computers: $($allComputers.Count)" -ForegroundColor Yellow
    Write-Host "Groups: $($allGroups.Count)" -ForegroundColor Yellow
    Write-Host "Outputs in: $($layout.RunRoot)" -ForegroundColor Yellow
    Write-Host ""

    return [pscustomobject]@{
        RunId                = $adDiscoveryLogContext.RunId
        DiagnosticLogPath    = $adDiscoveryLogContext.EventsPath
        IncompleteOperations = $outcome.IncompleteOperations
        LoggingFailed        = $adDiscoveryLogContext.LoggingFailed
        LoggingErrors        = $adDiscoveryLogContext.LoggingErrors.ToArray()
        Status               = $status
        FailedOperationCount = $failedOperations.Count
        FailedOperations     = $failedOperations
        ExecutionStatusPath  = $executionStatusPath
        RunRoot              = $layout.RunRoot
        LogPath              = $adDiscoveryLogContext.LogPath
        Environment          = $Environment
        ForestName           = $forest.Name
        DomainCount          = $domains.Count
        UserCount            = $allUsers.Count
        ComputerCount        = $allComputers.Count
        GroupCount           = $allGroups.Count
        ExecutionTime        = $Now
    }
}
