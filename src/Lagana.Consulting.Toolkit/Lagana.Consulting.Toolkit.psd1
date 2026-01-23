@{
  RootModule        = 'Lagana.Consulting.Toolkit.psm1'
  ModuleVersion     = '0.1.1'
  GUID              = '8593c972-06bc-4b0a-a680-0a61fcda0c3e'
  Author            = 'Lagana Consulting'
  CompanyName       = 'Lagana Consulting'
  Copyright         = '(c) Lagana Consulting. All rights reserved.'
  Description       = 'Server-side PowerShell toolkit for AD discovery and ADMT operations (PowerShell 5.1+).'
  PowerShellVersion = '5.1'

  FunctionsToExport = @(
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
    'Get-LcAdOrganizationalUnits'

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
    'Test-LcAdmtTrustPath',
    'Get-LcAdmtPasswordExportReadiness',
    'New-LcAdmtIncludeFiles',
    'Find-LcAdObjectConflicts',
    'Export-LcAdmtIncludeFileUsers',
    'Export-LcAdmtIncludeFileGroups',
    'Export-LcAdmtIncludeFileComputers',
    'Export-LcAdmtOptionFile'

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
