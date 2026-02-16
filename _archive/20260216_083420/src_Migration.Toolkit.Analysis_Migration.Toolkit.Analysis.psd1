@
@{
  CmdletsToExport = @(
  )
  AliasesToExport = @(
  )
  RootModule = 'Migration.Toolkit.Analysis.psm1'
  GUID = '26a638ce-362a-4514-a567-5b93d9e050ba'
  ModuleVersion = '0.1.0'
  Author = 'Paul Lagana'
  FunctionsToExport = @(
    'Export-AdCsvSafe'
    'Get-AdSchemaDefinitions'
    'New-AdAssessmentReport'
    'New-AdComprehensiveAssessmentReport'
    'New-AdMigrationPlanningReport'
    'New-AdEnvironmentComparisonReport'
    'New-AdMigrationReadinessChecklist'
    'New-AdEnvironmentSummaryDocument'
    'Invoke-AdDiscoveryComparison'
    'Invoke-AdDiscoveryAnalysis'
    'Invoke-AdCrossForestDuplicateCheck'
  )
  PowerShellVersion = '7.0'
  CompanyName = 'Paul Lagana'
  Copyright = '(c) Paul Lagana. All rights reserved.'
  VariablesToExport = @(
  )
  Description = 'Client-side analysis and reporting toolkit for AD assessments (PowerShell 7.0+).'
  PrivateData = 
Name                           Value
----                           -----
PSData                         {[ProjectUri, ], [Tags, System.Object[]], [ReleaseNotes, Initial release - client-side analysis and reporting functions requiring PowerShell 7.0+.], [LicenseUri, ]}
  RequiredModules = @(
    'Consulting.Toolkit.Discovery'
  )
}

