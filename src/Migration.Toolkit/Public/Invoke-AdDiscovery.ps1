function Invoke-AdDiscovery {
    <#
  .SYNOPSIS
  Performs comprehensive Active Directory discovery and assessment.

  .DESCRIPTION
  Discovers and analyzes an Active Directory environment, generating detailed CSV reports
  covering:
  - Forest topology (sites, trusts, UPN suffixes)
  - Domain infrastructure (DCs, password policies, GPOs)
  - Identity objects (users, groups, computers, OUs)
  - Security analysis (privileged accounts, encryption, SID history)
  - Extended assessments (group nesting, cross-domain membership, stale objects)
  - Migration risk flags and assessment summary

  Creates a timestamped directory structure with organized CSV outputs suitable for
  offline analysis and reporting.

  .PARAMETER Environment
  Environment label for this discovery run (e.g., "Source", "Target", "Production").
  Used in folder naming and manifest. Default is "Source".

  .PARAMETER OutputRoot
  Root directory where discovery output folder will be created.
  Default is "c:\scripts\Reports".

  .PARAMETER Prefix
  Custom prefix for the run folder name. If not specified, uses the forest root domain
  name (e.g., "AD_contoso.com"). Final folder: {Prefix}_{Timestamp}

  .PARAMETER CustomerName
  Customer or organization name for manifest metadata. Optional.

  .PARAMETER StaleUserThresholdDays
  Days since last logon to consider a user account stale. Default is 180.

  .PARAMETER StaleComputerThresholdDays
  Days since last logon to consider a computer account stale. Default is 90.

  .EXAMPLE
  Invoke-AdDiscovery

  Runs discovery for the current forest using default settings.
  Output: c:\scripts\Reports\AD_{forestname}_{timestamp}\

  .EXAMPLE
  Invoke-AdDiscovery -Environment "Production" -OutputRoot "D:\ADReports"

  Runs discovery labeled as "Production" environment with custom output location.

  .EXAMPLE
  Invoke-AdDiscovery -Environment "Source" -CustomerName "Contoso Corp" -Prefix "Contoso_PreMigration"

  Runs discovery with custom prefix and customer name in manifest.

  .EXAMPLE
  Invoke-AdDiscovery -StaleUserThresholdDays 90 -StaleComputerThresholdDays 60

  Runs discovery with custom staleness thresholds.

  .OUTPUTS
  PSCustomObject with discovery run information:
  - RunRoot (path to discovery output folder)
  - LogPath (path to discovery log file)
  - Environment (environment label)
  - ForestName (discovered forest name)
  - DomainCount (number of domains)
  - UserCount, ComputerCount, GroupCount (total objects)

  .NOTES
  Requires:
  - Active Directory PowerShell module (RSAT)
  - Domain-joined Windows host or appropriate credentials
  - Read access to AD forest/domains

  Discovery run structure:
  {RunRoot}\
    ├── 00_schemas\       (CSV schema definitions)
    ├── 10_forest\        (Forest-level data)
    ├── 20_domains\       (Per-domain data)
    │   └── Domain-{FQDN}\
    ├── 90_logs\          (Discovery logs)
    └── 99_manifest\      (Run metadata)

  .LINK
  Get-AdAdForest
  New-AdRunLayout
  Get-AdAssessmentSummary
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
        [int]$StaleUserThresholdDays = 180,

        [Parameter()]
        [int]$StaleComputerThresholdDays = 90
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $Now = Get-Date
    $EnvironmentSafeTag = $Environment.ToLower().Replace(' ', '_')

    $LegacyWorkstationOsRegex = '(?i)Windows (XP|Vista|7|8|8\.1|2000)'
    $LegacyServerOsRegex = '(?i)Windows Server (2003|2008|2008 R2|2012|2012 R2)'

    # Verify required functions are available
    if (-not (Get-Command Export-AdCsvSafe -ErrorAction SilentlyContinue)) {
        throw "Export-AdCsvSafe not found. Ensure Migration.Toolkit module is properly loaded."
    }

    if (-not (Get-Command Export-AdSchemas -ErrorAction SilentlyContinue)) {
        throw "Export-AdSchemas not found. Ensure Migration.Toolkit module is properly loaded."
    }

    function Get-DomainScopeTag([string]$DomainFqdn) {
        return ("Domain-{0}" -f $DomainFqdn)
    }

    # Discover forest early so we can name the run folder with the forest root domain
    Write-Host "Discovering Active Directory forest..." -ForegroundColor Cyan
    $forest = Get-AdAdForest
    $domains = @(Get-AdAdDomains -Forest $forest)
    $suffixSet = Get-AdKnownUpnSuffixes -Forest $forest -Domains $domains -AsHashSet

    Write-Host "  Forest: $($forest.Name)" -ForegroundColor Green
    Write-Host "  Domains: $(@($domains).Count)" -ForegroundColor Green

    # Build a default prefix based on forest root domain when not explicitly provided
    $rootDomainTag = if ([string]::IsNullOrWhiteSpace($forest.RootDomain)) { 'UnknownDomain' } else { $forest.RootDomain.ToLower().Replace(' ', '_') }
    $basePrefix = if ($PSBoundParameters.ContainsKey('Prefix') -and -not [string]::IsNullOrWhiteSpace($Prefix)) {
        $Prefix
    } else {
        "AD_{0}" -f $rootDomainTag
    }

    # -------------------------
    # Run layout + folders
    # -------------------------
    $EnvironmentPrefix = if ($EnvironmentSafeTag -eq "source") { $basePrefix } else { "${basePrefix}__${EnvironmentSafeTag}" }
    $layout = New-AdRunLayout -OutputRoot $OutputRoot -Prefix $EnvironmentPrefix -CreateLog

    Write-Host "  Output: $($layout.RunRoot)" -ForegroundColor Yellow

    $schemasDir = Join-Path $layout.RunRoot '00_schemas'
    $forestDir = Join-Path $layout.RunRoot '10_forest'
    $domainsRoot = Join-Path $layout.RunRoot '20_domains'
    $manifestDir = Join-Path $layout.RunRoot '99_manifest'
    $logsDir = Join-Path $layout.RunRoot '90_logs'

    foreach ($p in @($schemasDir, $forestDir, $domainsRoot, $manifestDir, $logsDir)) {
        if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }

    # -------------------------
    # Schemas
    # -------------------------
    Write-Host "`nExporting CSV schemas..." -ForegroundColor Cyan
    Export-AdSchemas -SchemasDir $schemasDir | Out-Null

    # -------------------------
    # Forest exports
    # -------------------------
    Write-Host "Exporting forest-level data..." -ForegroundColor Cyan

    (Get-AdAdForestSummary -Forest $forest) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Summary__Forest.csv') -Force -AllowEmpty

    (Get-AdAdForestUpnSuffixes -Forest $forest -Domains $domains) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Identity__UpnSuffixes__Forest.csv') -Force -AllowEmpty

    (Get-AdAdReplicationSites) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__Sites__Forest.csv') -Force -AllowEmpty

    (Get-AdAdReplicationSubnets) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__Subnets__Forest.csv') -Force -AllowEmpty

    (Get-AdAdReplicationSiteLinks) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Network__SiteLinks__Forest.csv') -Force -AllowEmpty

    (Get-AdAdForestTrusts -LogPath $layout.LogPath) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Security__Trusts__Forest.csv') -Force -AllowEmpty

    # -------------------------
    # Domain loop
    # -------------------------
    $allUsers = @()
    $allComputers = @()
    $allGroups = @()
    $allOus = @()
    $allGpos = @()
    $allPrivilegedAccounts = @()
    $allTombstone = @()
    $allGroupNesting = @()
    $allCrossDomainMembership = @()
    $allWeakPasswordPolicies = @()
    $allEmptyGroups = @()
    $allDuplicateSpns = @()
    $allTopSpns = @()
    $allOuDepth = @()
    $allDisabledAccounts = @()
    $allAdminSdHolder = @()
    $allDnsZones = @()
    $allDhcpScopes = @()
    $allSysvolSizes = @()
    $allTokenBloat = @()
    $allGpoPerformance = @()

    foreach ($d in $domains) {
        Write-Host "`nProcessing domain: $d" -ForegroundColor Cyan

        $ctx = Get-AdAdDomainContext -DomainFqdn $d -LogPath $layout.LogPath
        $scopeTag = Get-DomainScopeTag $ctx.DomainFqdn

        $domainDir = Join-Path $domainsRoot $scopeTag
        if (-not (Test-Path -LiteralPath $domainDir)) { New-Item -ItemType Directory -Path $domainDir -Force | Out-Null }

        # Domain summaries / infra
        Write-Host "  - Domain summary and infrastructure" -ForegroundColor Gray
        (Get-AdAdDomainSummary -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Summary__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdAdDomainControllers -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Infrastructure__DomainControllers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Password policy
        Write-Host "  - Password policies" -ForegroundColor Gray
        (Get-AdAdDefaultPasswordPolicy -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyDefault__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdAdFineGrainedPasswordPolicies -DomainContext $ctx -LogPath $layout.LogPath) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyFgpp__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdAdFineGrainedPasswordPolicyAssignments -DomainContext $ctx -LogPath $layout.LogPath) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PasswordPolicyFgppAssignments__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Structure / delegation
        Write-Host "  - Organizational units and delegation" -ForegroundColor Gray
        (Get-AdAdOrganizationalUnits -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Structure__OrganizationalUnits__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdAdOuDelegationAcls -DomainContext $ctx -Scope OneLevel) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__OuDelegationAcls__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Identity objects (keep materialized arrays if you reuse them)
        Write-Host "  - Identity objects (users, groups, computers)" -ForegroundColor Gray
        $groups = @(Get-AdAdGroups -DomainContext $ctx)
        $users = @(Get-AdAdUsers -DomainContext $ctx -Now $Now -KnownUpnSuffixSet $suffixSet)
        $comps = @(Get-AdAdComputers -DomainContext $ctx -Now $Now)
        $ous = @(Get-AdAdOrganizationalUnits -DomainContext $ctx)

        # Collect for forest-level assessment
        $allUsers += $users
        $allComputers += $comps
        $allGroups += $groups
        $allOus += $ous

        $groups |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Groups__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $users |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Users__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $comps |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ComputersAll__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Workstations vs servers split
        @($comps | Where-Object { -not $_.IsServer }) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ComputersWorkstations__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        @($comps | Where-Object { $_.IsServer }) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ComputersServers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Published resources
        Write-Host "  - Published resources" -ForegroundColor Gray
        (Get-AdAdPublishedPrinters -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Inventory__PublishedPrinters__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdAdPublishedSharedFolders -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Inventory__PublishedSharedFolders__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Stale objects
        Write-Host "  - Stale accounts analysis" -ForegroundColor Gray
        @($users | Where-Object { $_.LastLogonDays -and [int]$_.LastLogonDays -gt $StaleUserThresholdDays }) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__StaleUsers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        @($comps | Where-Object { -not $_.IsServer -and $_.LastLogonDays -and [int]$_.LastLogonDays -gt $StaleComputerThresholdDays }) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__StaleWorkstations__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        @($comps | Where-Object { $_.IsServer -and $_.LastLogonDays -and [int]$_.LastLogonDays -gt $StaleComputerThresholdDays }) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__StaleServers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Legacy OS
        Write-Host "  - Legacy operating systems" -ForegroundColor Gray
        @($comps | Where-Object { -not $_.IsServer -and $_.OperatingSystem -match $LegacyWorkstationOsRegex }) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__LegacyWorkstationOs__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        @($comps | Where-Object { $_.IsServer -and $_.OperatingSystem -match $LegacyServerOsRegex }) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__LegacyServerOs__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # SPNs
        Write-Host "  - Service Principal Names" -ForegroundColor Gray
        (Get-AdAdSpns -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Spns__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # SIDHistory, service candidates, privileged
        Write-Host "  - Security analysis (SID history, privileged accounts)" -ForegroundColor Gray
        (Get-AdUsersSidHistory -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__UsersSidHistory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdServiceAccountCandidates -DomainContext $ctx -Now $Now) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ServiceAccountCandidates__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $privAccounts = @(Get-AdPrivilegedAccounts -DomainContext $ctx)
        $allPrivilegedAccounts += $privAccounts
        $privAccounts |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__PrivilegedAccounts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # GPO inventory + links
        Write-Host "  - Group Policy Objects" -ForegroundColor Gray
        $gpos = @(Get-AdGpoInventory -DomainContext $ctx -LogPath $layout.LogPath)
        $allGpos += $gpos
        $gpos |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Inventory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdGpoLinks -DomainContext $ctx -Scope OneLevel) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Links__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Kerberos encryption focused datasets
        Write-Host "  - Kerberos encryption analysis" -ForegroundColor Gray
        $userKerb = $users | Select-Object DomainFqdn, SamAccountName, UserPrincipalName, EncryptionTypes, EncryptionRisk, SPNCount, SidHistoryCount, AdminCount
        @($userKerb) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__KerberosEncryptionUsers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Computers Kerberos encryption dataset
        $compKerb = $comps | Select-Object DomainFqdn, Name, DnsHostName, IsServer, EncryptionTypes, EncryptionRisk, SPNCount
        @($compKerb) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__KerberosEncryptionComputers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Extended assessment - Per-domain analysis
        Write-Host "  - Extended assessments" -ForegroundColor Gray

        $nestingDepth = @(Get-AdGroupNestingDepth -DomainContext $ctx)
        $allGroupNesting += $nestingDepth
        $nestingDepth |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__GroupNestingDepth__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $crossDomainMember = @(Get-AdCrossDomainGroupMembership -DomainContext $ctx)
        $allCrossDomainMembership += $crossDomainMember
        $crossDomainMember |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__CrossDomainGroupMembership__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $weakPwdPolicies = @(Get-AdWeakPasswordPolicies -DomainContext $ctx)
        $allWeakPasswordPolicies += $weakPwdPolicies
        $weakPwdPolicies |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__WeakPasswordPolicies__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $emptyGroups = @(Get-AdEmptyGroups -DomainContext $ctx)
        $allEmptyGroups += $emptyGroups
        $emptyGroups |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__EmptyGroups__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $dupSpns = @(Get-AdDuplicateSpns -DomainContext $ctx)
        $allDuplicateSpns += $dupSpns
        $dupSpns |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__DuplicateSpns__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $topSpns = @(Get-AdTopSpnsByType -DomainContext $ctx -Top 10)
        $allTopSpns += $topSpns
        $topSpns |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__TopSpnsByType__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $ouDepth = @(Get-AdOuDepthAnalysis -DomainContext $ctx)
        $allOuDepth += $ouDepth
        $ouDepth |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__OuDepthAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $disabledAccts = @(Get-AdDisabledAccounts -AllUsers $users -AllComputers $comps)
        $allDisabledAccounts += $disabledAccts
        $disabledAccts |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__DisabledAccounts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $adminSdHolder = @(Get-AdAdminSdHolderImpact -DomainContext $ctx)
        $allAdminSdHolder += $adminSdHolder
        $adminSdHolder |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__AdminSdHolderImpact__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # Tombstone lifetime per domain
        $tombstone = @(Get-AdTombstoneLifetime -DomainContext $ctx)
        $allTombstone += $tombstone
        $tombstone |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__TombstoneLifetime__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $dnsZones = @(Get-AdDnsZoneInventory -DomainFqdn $ctx.DomainFqdn -Server $ctx.Server)
        $allDnsZones += $dnsZones
        $dnsZones |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__DnsZoneInventory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $dhcpScopes = @(Get-AdDhcpScopeAnalysis -DomainFqdn $ctx.DomainFqdn -Server $ctx.Server)
        $allDhcpScopes += $dhcpScopes
        $dhcpScopes |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__DhcpScopeAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $sysvolSizes = @(Get-AdSysvolSizeAnalysis -DomainFqdn $ctx.DomainFqdn -Server $ctx.Server)
        $allSysvolSizes += $sysvolSizes
        $sysvolSizes |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__SysvolSizeAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $tokenBloat = @(Get-AdGroupTokenBloat -AllUsers $users)
        $allTokenBloat += $tokenBloat
        $tokenBloat |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__GroupTokenBloat__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $gpoPerf = @(Get-AdGpoPerformanceAnalysis -AllGpos $gpos)
        $allGpoPerformance += $gpoPerf
        $gpoPerf |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Analysis__GpoPerformanceAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
    }

    # -------------------------
    # Forest-level extended assessments
    # -------------------------
    Write-Host "`nRunning forest-level extended assessments..." -ForegroundColor Cyan

    $siteLinkData = @(Get-AdSiteLinkCostAnalysis)
    $siteLinkData |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Analysis__SiteLinkCostAnalysis__Forest.csv') -Force -AllowEmpty

    $fsmoData = @(Get-AdFsmoRoleAvailability -ForestName $($forest.Name))
    $fsmoData |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Analysis__FsmoRoleAvailability__Forest.csv') -Force -AllowEmpty

    $certServicesData = @(Get-AdCertificateServicesInventory -Forest $forest)
    $certServicesData |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Analysis__CertificateServicesInventory__Forest.csv') -Force -AllowEmpty

    $trustMapData = @(Get-AdTrustRelationshipMap -Forest $forest)
    $trustMapData |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Analysis__TrustRelationshipMap__Forest.csv') -Force -AllowEmpty

    # -------------------------
    # Assessment Summary & Migration Risk Flags
    # -------------------------
    Write-Host "Generating assessment summary and risk flags..." -ForegroundColor Cyan

    $assessmentSummary = Get-AdAssessmentSummary `
        -ForestName $forest.Name `
        -AllUsers @($allUsers) `
        -AllComputers @($allComputers) `
        -AllGroups @($allGroups) `
        -PrivilegedAccounts @($allPrivilegedAccounts) `
        -GroupNestingData @($allGroupNesting) `
        -CrossDomainMembershipData @($allCrossDomainMembership) `
        -WeakPasswordPoliciesData @($allWeakPasswordPolicies) `
        -EmptyGroupsData @($allEmptyGroups) `
        -DuplicateSpnsData @($allDuplicateSpns) `
        -DisabledAccountsData @($allDisabledAccounts) `
        -AdminSdHolderData @($allAdminSdHolder) `
        -FsmoAvailabilityData @($fsmoData) `
        -OuDepthData @($allOuDepth) `
        -TopSpnsData @($allTopSpns) `
        -SiteLinkData @($siteLinkData) `
        -TombstoneData @($allTombstone)

    $assessmentSummary |
    Export-AdCsvSafe -Path (Join-Path $layout.RunRoot 'AD__Assessment__Summary__Forest.csv') -Force

    $migrationRiskFlags = Get-AdMigrationRiskFlags -AllUsers @($allUsers) -AllComputers @($allComputers)
    $migrationRiskFlags |
    Export-AdCsvSafe -Path (Join-Path $layout.RunRoot 'AD__Migration__RiskFlags__Forest.csv') -Force -AllowEmpty

    $migrationRiskFlagsSummary = Get-AdMigrationRiskFlagsSummary -RiskFlagsData @($migrationRiskFlags)
    $migrationRiskFlagsSummary |
    Export-AdCsvSafe -Path (Join-Path $layout.RunRoot 'AD__Migration__RiskFlagsSummary__Forest.csv') -Force -AllowEmpty

    # -------------------------
    # Manifest (for assessment automation)
    # -------------------------
    Write-Host "Creating discovery manifest..." -ForegroundColor Cyan

    $allCsv = Get-ChildItem -Path $layout.RunRoot -Recurse -File -Filter *.csv -ErrorAction SilentlyContinue
    $manifest = foreach ($f in $allCsv) {
        $count = 0
        try { $count = (Import-Csv -Path $f.FullName).Count } catch { $count = 0 }

        [pscustomobject]@{
            FileName      = $f.Name
            RelativePath  = $f.FullName.Substring($layout.RunRoot.Length).TrimStart('\', '/')
            RowCount      = $count
            LastWriteTime = $f.LastWriteTime
        }
    }

    $manifestInfo = [pscustomobject]@{
        Environment   = $Environment
        ExecutionTime = $Now
        OutputRoot    = $layout.RunRoot
        Prefix        = $EnvironmentPrefix
        CustomerName  = $CustomerName
    }

    @($manifest) |
    Export-AdCsvSafe -Path (Join-Path $manifestDir 'Run__Manifest__Run.csv') -Force -AllowEmpty

    $manifestInfo | Export-AdCsvSafe -Path (Join-Path $manifestDir 'Run__Info__Run.csv') -Force

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
    Write-Host ""
    Write-Host "Outputs in: $($layout.RunRoot)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To generate reports, run:" -ForegroundColor Cyan
    Write-Host "  New-AdAssessmentReport -DiscoveryOutputPath '$($layout.RunRoot)'" -ForegroundColor White
    Write-Host "  New-AdComprehensiveAssessmentReport -DiscoveryOutputPath '$($layout.RunRoot)' -OutputPath '$(Join-Path $layout.RunRoot "LC__Assessment__Report__$EnvironmentSafeTag.html")'" -ForegroundColor White
    Write-Host ""

    # Return summary object
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
