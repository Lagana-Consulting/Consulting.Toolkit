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

    .OUTPUTS
    PSCustomObject with:
      RunRoot, LogPath, Environment, ForestName, DomainCount, UserCount, ComputerCount, GroupCount, ExecutionTime
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

        [switch]$IncludeSecurity
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Continue'

    $Now = Get-Date
    $EnvironmentSafeTag = $Environment.ToLower().Replace(' ', '_')

    # Track execution status (collector-style)
    $executionLog = @()
    function Log-ExecutionStatus {
        param([string]$Operation, [string]$Status, [string]$Message = "")
        $executionLog += [pscustomobject]@{
            Operation = $Operation
            Status    = $Status
            Message   = $Message
            Time      = Get-Date
        }
        if ($Message) {
            Write-Host "    [$Status] $Operation : $Message" -ForegroundColor $(if ($Status -eq 'OK') { 'Green' } else { 'Yellow' })
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

    try {
        $forest = Get-AdAdForest @forestParams
        $domains = @(Get-AdAdDomains -Forest $forest)
        $suffixSet = Get-AdKnownUpnSuffixes -Forest $forest -Domains $domains -AsHashSet
        Log-ExecutionStatus "Forest Discovery" "OK"
    } catch {
        Log-ExecutionStatus "Forest Discovery" "FAIL" $_.Exception.Message
        throw "Forest discovery failed. Cannot continue. $_"
    }

    Write-Host "  Forest: $($forest.Name)" -ForegroundColor Green
    Write-Host "  Domains: $(@($domains).Count)" -ForegroundColor Green

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

    if ($IncludeSecurity) {
        Write-Host "Exporting security datasets (forest)..." -ForegroundColor Cyan
        # Inline: Forest-level (ADCS) security exports
        if ($forestDir -and (Test-Path -LiteralPath $forestDir)) {
            function Try-Export {
                param([scriptblock]$Action, [string]$Operation)
                try {
                    & $Action
                    Write-Host "    [OK] $Operation" -ForegroundColor Green
                } catch {
                    Write-Host "    [WARN] $Operation : $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }

            Try-Export -Operation "ADCS Enterprise CAs (forest)" -Action {
                $cas = @(Get-AdSecurityAdcsInventory -Forest $forest -Mode EnterpriseCAs)
                $out = Join-Path $forestDir "AD__Forest__Security__ADCS__EnterpriseCAs__Forest.csv"
                $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                if ([string]::IsNullOrWhiteSpace($schemaName)) {
                    $cas | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                } else {
                    $cas | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                }
            }

            Try-Export -Operation "ADCS Enrollment Services Templates (forest)" -Action {
                $map = @(Get-AdSecurityAdcsInventory -Forest $forest -Mode EnrollmentServicesTemplates)
                $out = Join-Path $forestDir "AD__Forest__Security__ADCS__EnrollmentServicesTemplates__Forest.csv"
                $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                if ([string]::IsNullOrWhiteSpace($schemaName)) {
                    $map | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                } else {
                    $map | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                }
            }

            Try-Export -Operation "ADCS Certificate Templates (forest)" -Action {
                $templates = @(Get-AdSecurityCertificateTemplates -Forest $forest -Mode Templates)
                $out = Join-Path $forestDir "AD__Forest__Security__ADCS__CertificateTemplates__Forest.csv"
                $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                if ([string]::IsNullOrWhiteSpace($schemaName)) {
                    $templates | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                } else {
                    $templates | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                }
            }

            Try-Export -Operation "ADCS Certificate Template Permissions (forest)" -Action {
                $perms = @(Get-AdSecurityCertificateTemplates -Forest $forest -Mode TemplatePermissions)
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
    try {
        Export-AdSchemas -SchemasDir $schemasDir | Out-Null
        Log-ExecutionStatus "CSV Schemas Export" "OK"
    } catch {
        Log-ExecutionStatus "CSV Schemas Export" "FAIL" $_.Exception.Message
    }

    # -------------------------
    # Forest exports (collector)
    # -------------------------
    Write-Host "Exporting forest-level data..." -ForegroundColor Cyan

    try { (Get-AdAdForestSummary -Forest $forest) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Summary__Forest.csv') -Force -AllowEmpty } catch { Log-ExecutionStatus "Forest Summary" "FAIL" $_.Exception.Message }
    try { (Get-AdAdForestUpnSuffixes -Forest $forest -Domains $domains) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Identity__UpnSuffixes__Forest.csv') -Force -AllowEmpty } catch { Log-ExecutionStatus "Forest UPN Suffixes" "FAIL" $_.Exception.Message }
    try { (Get-AdAdReplicationSites) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__Sites__Forest.csv') -Force -AllowEmpty } catch { Log-ExecutionStatus "Replication Sites" "FAIL" $_.Exception.Message }

    try { (Get-AdAdReplicationSubnets)   | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__Subnets__Forest.csv')   -Force -AllowEmpty } catch { Log-ExecutionStatus "Replication Subnets" "FAIL" $_.Exception.Message }
    try { (Get-AdAdReplicationSiteLinks) | Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__SiteLinks__Forest.csv') -Force -AllowEmpty } catch { Log-ExecutionStatus "Replication SiteLinks" "FAIL" $_.Exception.Message }
    try { (Get-AdAdForestTrusts -LogPath $layout.LogPath) | Export-AdCsvSafeWithSchema -Path (Join-Path $forestDir 'AD__Forest__Security__Trusts__Forest.csv') -Force -AllowEmpty } catch { Log-ExecutionStatus "Forest Trusts" "FAIL" $_.Exception.Message }

    # -------------------------
    # Domain loop (collector)
    # -------------------------
    $allUsers = @()
    $allComputers = @()
    $allGroups = @()

    foreach ($d in $domains) {
        Write-Host "`nProcessing domain: $d" -ForegroundColor Cyan

        try {
            $ctxParams = @{ DomainFqdn = $d; LogPath = $layout.LogPath }
            if (-not [string]::IsNullOrWhiteSpace($Server)) { $ctxParams['Server'] = $Server }
            $ctx = Get-AdAdDomainContext @ctxParams

            $scopeTag = Get-DomainScopeTag $ctx.DomainFqdn
            $domainDir = Join-Path $domainsRoot $scopeTag
            if (-not (Test-Path -LiteralPath $domainDir)) { New-Item -ItemType Directory -Path $domainDir -Force | Out-Null }

            if ($IncludeSecurity) {
                Write-Host "  - Security discovery (tier0/delegation/adcs signals)" -ForegroundColor Gray
                # Inline: Domain-level security exports
                if ($domainDir -and (Test-Path -LiteralPath $domainDir)) {
                    function Try-Export {
                        param([scriptblock]$Action, [string]$Operation)
                        try {
                            & $Action
                            Write-Host "    [OK] $Operation" -ForegroundColor Green
                        } catch {
                            Write-Host "    [WARN] $Operation : $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                    }

                    Try-Export -Operation "Tier0 inventory (domain)" -Action {
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

                    Try-Export -Operation "AdminSDHolder impact (domain)" -Action {
                        $adminSd = @(Get-AdAdminSdHolderImpact -DomainContext $ctx)
                        $out = Join-Path $domainDir ("AD__Domain__Security__AdminSdHolderImpact__{0}.csv" -f $scopeTag)
                        $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                        if ([string]::IsNullOrWhiteSpace($schemaName)) {
                            $adminSd | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                        } else {
                            $adminSd | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                        }
                    }

                    Try-Export -Operation "Delegation inventory (domain)" -Action {
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

                    Try-Export -Operation "SPN Accounts inventory (domain)" -Action {
                        $spn = @(Get-AdSecuritySpnAccounts -DomainContext $ctx)
                        $out = Join-Path $domainDir ("AD__Domain__Security__SpnAccounts__{0}.csv" -f $scopeTag)
                        $schemaName = Resolve-AdSchemaNameForCsv -Path $out
                        if ([string]::IsNullOrWhiteSpace($schemaName)) {
                            $spn | Export-AdCsvSafe -Path $out -Force -AllowEmpty
                        } else {
                            $spn | Export-AdCsvSafe -Path $out -SchemaName $schemaName -Force -AllowEmpty
                        }
                    }

                    Try-Export -Operation "Domain Controller security signals (best effort)" -Action {
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
            (Get-AdAdDomainSummary -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Summary__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdAdDomainControllers -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Infrastructure__DomainControllers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            # Password policies (collector: raw policy datasets)
            Write-Host "  - Password policies" -ForegroundColor Gray
            (Get-AdAdDefaultPasswordPolicy -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyDefault__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdAdFineGrainedPasswordPolicies -DomainContext $ctx -LogPath $layout.LogPath) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyFgpp__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdAdFineGrainedPasswordPolicyAssignments -DomainContext $ctx -LogPath $layout.LogPath) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyFgppAssignments__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            # Structure / delegation (collector)
            Write-Host "  - Organizational units and delegation" -ForegroundColor Gray
            (Get-AdAdOrganizationalUnits -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Structure__OrganizationalUnits__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdAdOuDelegationAcls -DomainContext $ctx -Scope OneLevel) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__OuDelegationAcls__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            # Identity objects (collector: full sets)
            Write-Host "  - Identity objects (users, groups, computers)" -ForegroundColor Gray
            $groups = @(Get-AdAdGroups -DomainContext $ctx)
            $users = @(Get-AdAdUsers  -DomainContext $ctx -Now $Now -KnownUpnSuffixSet $suffixSet)
            $comps = @(Get-AdAdComputers -DomainContext $ctx -Now $Now)

            $allGroups += $groups
            $allUsers += $users
            $allComputers += $comps

            $groups | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Groups__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            $users  | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Users__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
            $comps  | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ComputersAll__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            # Published resources (collector)
            Write-Host "  - Published resources" -ForegroundColor Gray
            (Get-AdAdPublishedPrinters -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Inventory__PublishedPrinters__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdAdPublishedSharedFolders -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Inventory__PublishedSharedFolders__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            # Contacts (collector) — use function signature you currently have
            Write-Host "  - AD Contacts" -ForegroundColor Gray
            (Get-AdAdContacts -DomainName $ctx.DomainFqdn -Server $ctx.DomainController) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Contacts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            # SPNs (collector)
            Write-Host "  - Service Principal Names" -ForegroundColor Gray
            (Get-AdAdSpns -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Spns__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            # Security inventory (collector: raw facts, no scoring)
            Write-Host "  - Security inventory (SID history, privileged accounts, service candidates)" -ForegroundColor Gray
            (Get-AdUsersSidHistory -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__UsersSidHistory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdServiceAccountCandidates -DomainContext $ctx -Now $Now) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ServiceAccountCandidates__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdPrivilegedAccounts -DomainContext $ctx) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PrivilegedAccounts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            if ($IncludeSecurity) {
                # -------------------------
                # Phase 1 Security exports (raw facts only)
                # -------------------------
                Write-Host "  - Security (Phase 1: account/kerberos/gpo raw facts)" -ForegroundColor DarkGray

                try {
                    (Get-AdRecentlyCreatedObjects -DomainContext $ctx -Days 10 -IncludeGpo -LogPath $layout.LogPath) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__RecentlyCreatedObjects__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                } catch { Log-ExecutionStatus "Recently Created Objects ($d)" "FAIL" $_.Exception.Message }

                try {
                    (Get-AdBuiltInAdministratorSignals -DomainContext $ctx) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__BuiltInAdministratorSignals__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                } catch { Log-ExecutionStatus "Built-in Administrator Signals ($d)" "FAIL" $_.Exception.Message }

                try {
                    (Get-AdAsrepRoastableUsers -DomainContext $ctx) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__AsrepRoastableUsers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                } catch { Log-ExecutionStatus "AS-REP Roastable Users ($d)" "FAIL" $_.Exception.Message }

                try {
                    (Get-AdPrivilegedPasswordAge -DomainContext $ctx) |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__Security__PrivilegedPasswordAge__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                } catch { Log-ExecutionStatus "Privileged Password Age ($d)" "FAIL" $_.Exception.Message }

                try {
                    $gpoDelegation = @(Get-AdGpoDelegation -DomainContext $ctx -LogPath $layout.LogPath)
                    $gpoDelegation |
                    Export-AdCsvSafeWithSchema -Path (Join-Path $domainDir ("AD__Domain__GPO__Delegation__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
                } catch { Log-ExecutionStatus "GPO Delegation ($d)" "FAIL" $_.Exception.Message }
            }

            # GPO inventory + links (collector)
            Write-Host "  - Group Policy Objects" -ForegroundColor Gray
            $gpos = @(Get-AdGpoInventory -DomainContext $ctx -LogPath $layout.LogPath)
            $gpos | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Inventory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            (Get-AdGpoLinks -DomainContext $ctx -Scope Subtree -LogPath $layout.LogPath) |
            Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Links__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

            Log-ExecutionStatus "Domain Processing ($d)" "OK"
        } catch {
            Log-ExecutionStatus "Domain Processing ($d)" "FAIL" $_.Exception.Message
            Write-Host "  Skipping domain due to error: $_" -ForegroundColor Red
            continue
        }
    }

    # -------------------------
    # Manifest (collector metadata only)
    # -------------------------
    Write-Host "`nCreating run manifest..." -ForegroundColor Cyan

    try {
        $allCsv = Get-ChildItem -Path $layout.RunRoot -Recurse -File -Filter *.csv -ErrorAction SilentlyContinue
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
        Log-ExecutionStatus "Run Manifest" "FAIL" $_.Exception.Message
    }

    # -------------------------
    # Completion summary
    # -------------------------
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Discovery Complete: $Environment Environment" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Forest: $($forest.Name)" -ForegroundColor Yellow
    Write-Host "Domains: $($domains.Count)" -ForegroundColor Yellow
    Write-Host "Users: $($allUsers.Count)" -ForegroundColor Yellow
    Write-Host "Computers: $($allComputers.Count)" -ForegroundColor Yellow
    Write-Host "Groups: $($allGroups.Count)" -ForegroundColor Yellow
    Write-Host "Outputs in: $($layout.RunRoot)" -ForegroundColor Yellow
    Write-Host ""

    return [pscustomobject]@{
        RunRoot       = $layout.RunRoot
        LogPath       = $layout.LogPath
        Environment   = $Environment
        ForestName    = $forest.Name
        DomainCount   = $domains.Count
        UserCount     = $allUsers.Count
        ComputerCount = $allComputers.Count
        GroupCount    = $allGroups.Count
        ExecutionTime = $Now
    }
}
