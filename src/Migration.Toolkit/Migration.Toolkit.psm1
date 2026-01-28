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
  'New-AdLog',
  'Write-AdLog',
  'Export-AdCsv',
  'Export-AdCsvSafe',
  'Get-AdSchemaDefinitions',
  'Export-AdSchemas',
  'Write-AdSchemaCsv',

  # Tenant safety / auth
  'Confirm-AdTenant',
  'Connect-AdGraph',

  # Run layout
  'New-AdRunLayout',

  # Forest + domains
  'Get-AdAdForest',
  'Get-AdAdDomains',
  'Get-AdKnownUpnSuffixes',

  'Get-AdAdForestSummary',
  'Get-AdAdForestUpnSuffixes',
  'Get-AdAdReplicationSites',
  'Get-AdAdReplicationSubnets',
  'Get-AdAdReplicationSiteLinks',
  'Get-AdAdForestTrusts',

  'Get-AdAdDomainContext',
  'New-AdDomainRunFolder',

  'Get-AdAdDomainSummary',
  'Get-AdAdDomainControllers',
  'Get-AdAdDefaultPasswordPolicy',
  'Get-AdAdFineGrainedPasswordPolicies',
  'Get-AdAdFineGrainedPasswordPolicyAssignments',
  'Get-AdAdOrganizationalUnits',

  'Get-AdAdPublishedPrinters',
  'Get-AdAdPublishedSharedFolders',

  'Get-AdAdGroups',
  'Get-AdAdUsers',
  'Get-AdAdComputers',
  'Get-AdAdSpns',

  'Get-AdAdOuDelegationAcls',
  'Get-AdGpoInventory',
  'Get-AdGpoLinks',
  'Get-AdUsersSidHistory',
  'Get-AdServiceAccountCandidates',
  'Get-AdPrivilegedAccounts',
  'Get-AdRiskSummary',
  'Get-AdAssessmentSummary',
  'Get-AdMigrationRiskFlags',
  'Get-AdMigrationRiskFlagsSummary',

  # Extended assessment / analysis
  'Get-AdGroupNestingDepth',
  'Get-AdCrossDomainGroupMembership',
  'Get-AdWeakPasswordPolicies',
  'Get-AdEmptyGroups',
  'Get-AdDuplicateSpns',
  'Get-AdTopSpnsByType',
  'Get-AdOuDepthAnalysis',
  'Get-AdDisabledAccounts',
  'Get-AdAdminSdHolderImpact',
  'Get-AdTombstoneLifetime',
  'Get-AdSiteLinkCostAnalysis',
  'Get-AdFsmoRoleAvailability',
  'Get-AdCertificateServicesInventory',
  'Get-AdDnsZoneInventory',
  'Get-AdDhcpScopeAnalysis',
  'Get-AdSysvolSizeAnalysis',
  'Get-AdDuplicateObjectsForAdmt',
  'Get-AdGroupTokenBloat',
  'Get-AdTrustRelationshipMap',
  'Get-AdGpoPerformanceAnalysis',

  #ADMT Functions
  'New-AdAdmtRunLayout',
  'Test-AdAdmtPrereqs',
  'Test-AdAdmtTrustPath',
  'Get-AdAdmtPasswordExportReadiness',
  'New-AdAdmtIncludeFiles',
  'Find-AdAdObjectConflicts',
  'Export-AdAdmtIncludeFileUsers',
  'Export-AdAdmtIncludeFileGroups',
  'Export-AdAdmtIncludeFileComputers',
  'Export-AdAdmtOptionFile'
)
