@{
  RootModule        = 'Migration.Toolkit.psm1'
  ModuleVersion     = '0.1.1'
  GUID              = '7a3e2d92-6df5-4043-88bd-d332cfec4f65'
  Author            = 'Paul Lagana'
  CompanyName       = 'Paul Lagana'
  Copyright         = '(c) Paul Lagana. All rights reserved.'
  Description       = 'Server-side PowerShell toolkit for AD discovery and ADMT operations (PowerShell 5.1+).'
  PowerShellVersion = '5.1'

  FunctionsToExport = @(
    # Logging / export
    'New-AdLog',
    'Write-AdLog',
    'Export-AdCsv',

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

  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData       = @{
    PSData = @{
      Tags         = @('PowerShell', 'Toolkit', 'Consulting', 'ActiveDirectory', 'MicrosoftGraph')
      ProjectUri   = ''
      LicenseUri   = ''
      ReleaseNotes = 'Weak policy property fix; extended assessments integration and discovery updates.'
    }
  }
}
