[CmdletBinding()]
param(
  [string]$Environment = "Source",
  [string]$OutputRoot = "c:\scripts\Reports",
  [string]$Prefix = "ADOnly",
  [string]$CustomerName = ""
)

$ModulePsd1 = 'c:\scripts\modules\Lagana.Consulting.Toolkit\Lagana.Consulting.Toolkit.psd1'
Import-Module (Resolve-Path $ModulePsd1).Path -Force

#requires -Modules Lagana.Consulting.Toolkit
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Now = Get-Date
$EnvironmentSafeTag = $Environment.ToLower().Replace(' ', '_')


if (-not (Get-Command Export-LcCsvSafe -ErrorAction SilentlyContinue)) {
  throw "Export-LcCsvSafe not found. Update/import Lagana.Consulting.Toolkit that includes Export-LcCsvSafe."
}

if (-not (Get-Command Export-LcSchemas -ErrorAction SilentlyContinue)) {
  throw "Export-LcSchemas not found. Update/import Lagana.Consulting.Toolkit that includes Export-LcSchemas."
}


function Get-DomainScopeTag([string]$DomainFqdn) {
  return ("Domain-{0}" -f $DomainFqdn)
}

# -------------------------
# Run layout + folders
# -------------------------
$EnvironmentPrefix = if ($EnvironmentSafeTag -eq "source") { $Prefix } else { "${Prefix}__${EnvironmentSafeTag}" }
$layout = New-LcRunLayout -OutputRoot $OutputRoot -Prefix $EnvironmentPrefix -CreateLog

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
Export-LcSchemas -SchemasDir $schemasDir | Out-Null

# -------------------------
# Forest + domains
# -------------------------
$forest = Get-LcAdForest
$domains = Get-LcAdDomains -Forest $forest
$suffixSet = Get-LcKnownUpnSuffixes -Forest $forest -Domains $domains -AsHashSet

# -------------------------
# Forest exports
# -------------------------
(Get-LcAdForestSummary -Forest $forest) |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Summary__Forest.csv') -Force -AllowEmpty

(Get-LcAdForestUpnSuffixes -Forest $forest -Domains $domains) |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Identity__UpnSuffixes__Forest.csv') -Force -AllowEmpty

(Get-LcAdReplicationSites) |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Network__Sites__Forest.csv') -Force -AllowEmpty

(Get-LcAdReplicationSubnets) |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Network__Subnets__Forest.csv') -Force -AllowEmpty

(Get-LcAdReplicationSiteLinks) |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Network__SiteLinks__Forest.csv') -Force -AllowEmpty

(Get-LcAdForestTrusts -LogPath $layout.LogPath) |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Security__Trusts__Forest.csv') -Force -AllowEmpty

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
  $ctx = Get-LcAdDomainContext -DomainFqdn $d -LogPath $layout.LogPath
  $scopeTag = Get-DomainScopeTag $ctx.DomainFqdn

  $domainDir = Join-Path $domainsRoot $scopeTag
  if (-not (Test-Path -LiteralPath $domainDir)) { New-Item -ItemType Directory -Path $domainDir -Force | Out-Null }

  # Domain summaries / infra
  (Get-LcAdDomainSummary -DomainContext $ctx) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Summary__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  (Get-LcAdDomainControllers -DomainContext $ctx) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Infrastructure__DomainControllers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Password policy
  (Get-LcAdDefaultPasswordPolicy -DomainContext $ctx) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__PasswordPolicyDefault__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  (Get-LcAdFineGrainedPasswordPolicies -DomainContext $ctx -LogPath $layout.LogPath) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__PasswordPolicyFgpp__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  (Get-LcAdFineGrainedPasswordPolicyAssignments -DomainContext $ctx -LogPath $layout.LogPath) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__PasswordPolicyFgppAssignments__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Structure / delegation
  (Get-LcAdOrganizationalUnits -DomainContext $ctx) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Structure__OrganizationalUnits__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  (Get-LcAdOuDelegationAcls -DomainContext $ctx -Scope OneLevel) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__OuDelegationAcls__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Identity objects (keep materialized arrays if you reuse them)
  $groups = @(Get-LcAdGroups -DomainContext $ctx)
  $users = @(Get-LcAdUsers -DomainContext $ctx -Now $Now -KnownUpnSuffixSet $suffixSet)
  $comps = @(Get-LcAdComputers -DomainContext $ctx -Now $Now)
  $ous = @(Get-LcAdOrganizationalUnits -DomainContext $ctx)

  # Collect for forest-level assessment
  $allUsers += $users
  $allComputers += $comps
  $allGroups += $groups
  $allOus += $ous

  $groups |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Identity__Groups__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $users |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Identity__Users__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $comps |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Identity__ComputersAll__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Workstations vs servers split
  @($comps | Where-Object { -not $_.IsServer }) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Identity__ComputersWorkstations__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  @($comps | Where-Object { $_.IsServer }) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Identity__ComputersServers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # SPNs
  (Get-LcAdSpns -DomainContext $ctx) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Identity__Spns__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # SIDHistory, service candidates, privileged
  (Get-LcUsersSidHistory -DomainContext $ctx) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__UsersSidHistory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  (Get-LcServiceAccountCandidates -DomainContext $ctx -Now $Now) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Identity__ServiceAccountCandidates__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $privAccounts = @(Get-LcPrivilegedAccounts -DomainContext $ctx)
  $allPrivilegedAccounts += $privAccounts
  $privAccounts |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__PrivilegedAccounts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # GPO inventory + links
  $gpos = @(Get-LcGpoInventory -DomainContext $ctx -LogPath $layout.LogPath)
  $allGpos += $gpos
  $gpos |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__GPO__Inventory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  (Get-LcGpoLinks -DomainContext $ctx -Scope OneLevel) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__GPO__Links__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Kerberos encryption focused datasets
  $userKerb = $users | Select-Object DomainFqdn, SamAccountName, UserPrincipalName, EncryptionTypes, EncryptionRisk, SPNCount, SidHistoryCount, AdminCount
  @($userKerb) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__KerberosEncryptionUsers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Computers Kerberos encryption dataset
  $compKerb = $comps | Select-Object DomainFqdn, Name, DnsHostName, IsServer, EncryptionTypes, EncryptionRisk, SPNCount
  @($compKerb) |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Security__KerberosEncryptionComputers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Extended assessment - Per-domain analysis
  Write-Host "Running extended assessments for $($ctx.DomainFqdn)..."

  $nestingDepth = @(Get-LcGroupNestingDepth -DomainContext $ctx)
  $allGroupNesting += $nestingDepth
  $nestingDepth |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__GroupNestingDepth__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $crossDomainMember = @(Get-LcCrossDomainGroupMembership -DomainContext $ctx)
  $allCrossDomainMembership += $crossDomainMember
  $crossDomainMember |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__CrossDomainGroupMembership__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $weakPwdPolicies = @(Get-LcWeakPasswordPolicies -DomainContext $ctx)
  $allWeakPasswordPolicies += $weakPwdPolicies
  $weakPwdPolicies |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__WeakPasswordPolicies__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $emptyGroups = @(Get-LcEmptyGroups -DomainContext $ctx)
  $allEmptyGroups += $emptyGroups
  $emptyGroups |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__EmptyGroups__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $dupSpns = @(Get-LcDuplicateSpns -DomainContext $ctx)
  $allDuplicateSpns += $dupSpns
  $dupSpns |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__DuplicateSpns__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $topSpns = @(Get-LcTopSpnsByType -DomainContext $ctx -Top 10)
  $allTopSpns += $topSpns
  $topSpns |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__TopSpnsByType__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $ouDepth = @(Get-LcOuDepthAnalysis -DomainContext $ctx)
  $allOuDepth += $ouDepth
  $ouDepth |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__OuDepthAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $disabledAccts = @(Get-LcDisabledAccounts -AllUsers $users -AllComputers $comps)
  $allDisabledAccounts += $disabledAccts
  $disabledAccts |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__DisabledAccounts__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $adminSdHolder = @(Get-LcAdminSdHolderImpact -DomainContext $ctx)
  $allAdminSdHolder += $adminSdHolder
  $adminSdHolder |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__AdminSdHolderImpact__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  # Tombstone lifetime per domain
  $tombstone = @(Get-LcTombstoneLifetime -DomainContext $ctx)
  $allTombstone += $tombstone
  $tombstone |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__TombstoneLifetime__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $dnsZones = @(Get-LcDnsZoneInventory -DomainFqdn $ctx.DomainFqdn -Server $ctx.Server)
  $allDnsZones += $dnsZones
  $dnsZones |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__DnsZoneInventory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $dhcpScopes = @(Get-LcDhcpScopeAnalysis -DomainFqdn $ctx.DomainFqdn -Server $ctx.Server)
  $allDhcpScopes += $dhcpScopes
  $dhcpScopes |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__DhcpScopeAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $sysvolSizes = @(Get-LcSysvolSizeAnalysis -DomainFqdn $ctx.DomainFqdn -Server $ctx.Server)
  $allSysvolSizes += $sysvolSizes
  $sysvolSizes |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__SysvolSizeAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $tokenBloat = @(Get-LcGroupTokenBloat -AllUsers $users)
  $allTokenBloat += $tokenBloat
  $tokenBloat |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__GroupTokenBloat__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

  $gpoPerf = @(Get-LcGpoPerformanceAnalysis -AllGpos $gpos)
  $allGpoPerformance += $gpoPerf
  $gpoPerf |
  Export-LcCsvSafe -Path (Join-Path $domainDir ("LC__AD__Domain__Analysis__GpoPerformanceAnalysis__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
}

# -------------------------
# Forest-level extended assessments
# -------------------------
Write-Host "Running forest-level extended assessments..."

$siteLinkData = @(Get-LcSiteLinkCostAnalysis)
$siteLinkData |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Analysis__SiteLinkCostAnalysis__Forest.csv') -Force -AllowEmpty

$fsmoData = @(Get-LcFsmoRoleAvailability -ForestName $($forest.Name))
$fsmoData |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Analysis__FsmoRoleAvailability__Forest.csv') -Force -AllowEmpty

$certServicesData = @(Get-LcCertificateServicesInventory -Forest $forest)
$certServicesData |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Analysis__CertificateServicesInventory__Forest.csv') -Force -AllowEmpty

$trustMapData = @(Get-LcTrustRelationshipMap -Forest $forest)
$trustMapData |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Analysis__TrustRelationshipMap__Forest.csv') -Force -AllowEmpty

$duplicateObjectsData = @(Get-LcDuplicateObjectsForAdmt -AllUsers $allUsers -AllComputers $allComputers -AllGroups $allGroups)
$duplicateObjectsData |
Export-LcCsvSafe -Path (Join-Path $forestDir 'LC__AD__Forest__Analysis__DuplicateObjectsForAdmt__Forest.csv') -Force -AllowEmpty

# -------------------------
# Aggregate analysis from all domains
# -------------------------
Write-Host "Preparing assessment summary data..."

# Note: Arrays ($allGroupNesting, $allTopSpns, etc.) were already collected and accumulated during the domain loop
# We use the in-memory arrays directly for assessment to preserve object types

# -------------------------
# Assessment Summary & Migration Risk Flags
# -------------------------
Write-Host "Generating assessment summary and risk flags..."

# Ensure all arrays are at least empty arrays, not $null
$assessmentSummary = Get-LcAssessmentSummary `
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
  -TombstoneData @($tombstoneData)

$assessmentSummary |
Export-LcCsvSafe -Path (Join-Path $layout.RunRoot 'LC__AD__Assessment__Summary__Forest.csv') -Force

$migrationRiskFlags = Get-LcMigrationRiskFlags -AllUsers @($allUsers) -AllComputers @($allComputers)
$migrationRiskFlags |
Export-LcCsvSafe -Path (Join-Path $layout.RunRoot 'LC__AD__Migration__RiskFlags__Forest.csv') -Force -AllowEmpty

$migrationRiskFlagsSummary = Get-LcMigrationRiskFlagsSummary -RiskFlagsData @($migrationRiskFlags)
$migrationRiskFlagsSummary |
Export-LcCsvSafe -Path (Join-Path $layout.RunRoot 'LC__AD__Migration__RiskFlagsSummary__Forest.csv') -Force -AllowEmpty


# -------------------------
# Manifest (for assessment automation)
# -------------------------
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

# -------------------------
# Manifest (for assessment automation)
# -------------------------
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
Export-LcCsvSafe -Path (Join-Path $manifestDir 'LC__Run__Manifest__Run.csv') -Force -AllowEmpty

$manifestInfo | Export-LcCsvSafe -Path (Join-Path $manifestDir 'LC__Run__Info__Run.csv') -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Discovery Complete: $Environment Environment" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Outputs in: $($layout.RunRoot)" -ForegroundColor Yellow
Write-Host ""
Write-Host "To generate reports, run:" -ForegroundColor Cyan
Write-Host "  New-LcAssessmentReport -RunRoot '$($layout.RunRoot)' -OutputPath '$(Join-Path $layout.RunRoot "LC__Assessment__Report__$EnvironmentSafeTag.html")'" -ForegroundColor White
Write-Host "  New-LcMigrationPlanningReport -RunRoot '$($layout.RunRoot)' -OutputPath '$(Join-Path $layout.RunRoot "LC__Migration__Planning__$EnvironmentSafeTag.html")'" -ForegroundColor White
Write-Host ""

