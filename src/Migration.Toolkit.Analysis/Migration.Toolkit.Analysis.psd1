@{
    RootModule        = 'Migration.Toolkit.Analysis.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '26a638ce-362a-4514-a567-5b93d9e050ba'
    Author            = 'Paul Lagana'
    CompanyName       = 'Paul Lagana'
    Copyright         = '(c) Paul Lagana. All rights reserved.'
    Description       = 'Client-side analysis and reporting toolkit for AD assessments (PowerShell 7.0+).'
    PowerShellVersion = '7.0'

    RequiredModules   = @('Migration.Toolkit')

    FunctionsToExport = @(
        # Schema and safe exports
        'Export-AdCsvSafe',
        'Get-AdSchemaDefinitions',
        'Export-AdSchemas',
        'Write-AdSchemaCsv',

        # Reports
        'New-AdAssessmentReport',
        'New-AdComprehensiveAssessmentReport',
        'New-AdMigrationPlanningReport',
        'New-AdMigrationLoeExcel',
        'New-AdEnvironmentComparisonReport',
        'New-AdMigrationReadinessChecklist',

        # Discovery orchestration
        'Invoke-AdDiscoveryComparison',
        'Invoke-AdDiscoveryAnalysis'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('PowerShell', 'Toolkit', 'Analysis', 'Reporting', 'ActiveDirectory')
            ProjectUri   = ''
            LicenseUri   = ''
            ReleaseNotes = 'Initial release - client-side analysis and reporting functions requiring PowerShell 7.0+.'
        }
    }
}
