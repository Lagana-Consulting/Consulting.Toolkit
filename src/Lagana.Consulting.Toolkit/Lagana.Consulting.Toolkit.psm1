Set-StrictMode -Version Latest

$PublicPath = Join-Path $PSScriptRoot 'Public'
$PrivatePath = Join-Path $PSScriptRoot 'Private'

# Dot-source Private first
Get-ChildItem -Path $PrivatePath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
  . $_.FullName
}

# Dot-source Public
Get-ChildItem -Path $PublicPath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
  . $_.FullName
}

# Export only public functions
Export-ModuleMember -Function @(
  # Logging / export
  'New-LcLog',
  'Write-LcLog',
  'Export-LcCsv',

  # Tenant safety / auth
  'Confirm-LcTenant',
  'Connect-LcGraph',

  # Run layout
  'New-LcRunLayout',

  # Forest + domains
  'Get-LcAdForest',
  'Get-LcAdDomains',
  'Get-LcKnownUpnSuffixes',

  'Get-LcAdForestSummary',
  'Get-LcAdForestUpnSuffixes',
  'Get-LcAdReplicationSites',
  'Get-LcAdReplicationSubnets',
  'Get-LcAdReplicationSiteLinks',
  'Get-LcAdForestTrusts',

  'Get-LcAdDomainContext',
  'New-LcDomainRunFolder',

  'Get-LcAdDomainSummary',
  'Get-LcAdDomainControllers',
  'Get-LcAdDefaultPasswordPolicy',
  'Get-LcAdFineGrainedPasswordPolicies',
  'Get-LcAdFineGrainedPasswordPolicyAssignments',
  'Get-LcAdOrganizationalUnits',

  'Get-LcAdGroups',
  'Get-LcAdUsers',
  'Get-LcAdComputers',
  'Get-LcAdSpns',

  'Get-LcAdOuDelegationAcls',
  'Get-LcGpoInventory',
  'Get-LcGpoLinks',
  'Get-LcUsersSidHistory',
  'Get-LcServiceAccountCandidates',
  'Get-LcPrivilegedAccounts',
  'Get-LcRiskSummary',
  'Get-LcAssessmentSummary',
  'Get-LcMigrationRiskFlags',
  'Get-LcMigrationRiskFlagsSummary',

  # Extended assessment / analysis
  'Get-LcGroupNestingDepth',
  'Get-LcCrossDomainGroupMembership',
  'Get-LcWeakPasswordPolicies',
  'Get-LcEmptyGroups',
  'Get-LcDuplicateSpns',
  'Get-LcTopSpnsByType',
  'Get-LcOuDepthAnalysis',
  'Get-LcDisabledAccounts',
  'Get-LcAdminSdHolderImpact',
  'Get-LcTombstoneLifetime',
  'Get-LcSiteLinkCostAnalysis',
  'Get-LcFsmoRoleAvailability',
  'Get-LcCertificateServicesInventory',
  'Get-LcDnsZoneInventory',
  'Get-LcDhcpScopeAnalysis',
  'Get-LcSysvolSizeAnalysis',
  'Get-LcDuplicateObjectsForAdmt',
  'Get-LcGroupTokenBloat',
  'Get-LcTrustRelationshipMap',
  'Get-LcGpoPerformanceAnalysis',

  #ADMT Functions
  'New-LcAdmtRunLayout',
  'Test-LcAdmtPrereqs',
  'Find-LcAdObjectConflicts',
  'Export-LcAdmtIncludeFileUsers',
  'Export-LcAdmtIncludeFileGroups',
  'Export-LcAdmtIncludeFileComputers',
  'Export-LcAdmtOptionFile'
)
