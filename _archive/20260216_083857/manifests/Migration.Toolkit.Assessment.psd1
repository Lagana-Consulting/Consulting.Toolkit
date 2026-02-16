@{
@{
  CmdletsToExport = @(
  )
  AliasesToExport = @(
  )
  RootModule = 'Migration.Toolkit.Assessment.psm1'
  GUID = '9bb6a36b-4f19-4f1a-8ff1-6d1e2a9b1ed6'
  ModuleVersion = '0.1.0'
  Author = 'Quest'
  FunctionsToExport = @(
    'Invoke-AdAssessment'
    'Invoke-ADOnlyAssessment'
    'Invoke-AZOnlyAssessment'
    'Invoke-FullAssessment'
    'Invoke-ADAssessmentAutomation'
    'Add-AdRawTableFromCsv'
    'Add-AdPivotTableFromCsv'
    'Add-AdUserStatsSummary'
    'Add-AdDeviceSummary'
    'Add-AdWorkstationSummary'
    'Add-AdServerSummary'
    'Add-AdOuStructureSummary'
    'Add-AdForestSummary'
    'Add-AdTrustInformation'
    'Add-AdDomainInformation'
    'Add-AdDomainControllers'
    'Add-AdPasswordPolicies'
    'Add-AdFineGrainPasswordPolicies'
    'Add-AdGPOSummary'
    'Add-AdGroupStatsSummary'
    'Add-AdContactsStatsSummary'
    'Add-AdPublishedPrinters'
    'Add-AdOUDepthSummary'
    'Add-AzEntraUserSummary'
    'Add-AzM365GroupSummary'
    'Add-AzMailboxSummary'
    'Add-AzOneDriveSummary'
    'Add-AzTeamsActivitySummary'
    'Add-AzSharePointSummary'
    'Add-AdSingleRowSummaryFromCsv'
    'Add-AdCountRowsSummary'
    'Add-AzEntraGuestDomainSummary'
    'Add-AdDomainDiscoveryTable'
    'Add-AdEmptyGroupsTable'
    'Add-AdServiceAccountsTable'
    'Add-AdSpnsTable'
    'Add-AdPrivilegedAccountsTable'
    'Add-AdForestRiskSummary'
    'Add-AdForestRiskFlags'
    'Add-AdDomainRiskSummary'
    'Add-AdDomainRiskFlags'
  )
  PowerShellVersion = '5.1'
  CompanyName = 'Quest'
  Copyright = '(c) 2026 Quest. All rights reserved.'
  VariablesToExport = @(
  )
  Description = 'Assessment module for AD, Entra, and M365 reporting using Word templates.'
  PrivateData = 
Name                           Value
PSData                         {[ProjectUri, ], [Tags, System.Object[]], [ReleaseNotes, Initial scaffold.], [LicenseUri, ]}
  RequiredModules = @(
    'Migration.Toolkit.Analysis'
  )
}

