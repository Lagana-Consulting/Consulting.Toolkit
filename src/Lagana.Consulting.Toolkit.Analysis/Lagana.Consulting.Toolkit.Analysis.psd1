@{
    RootModule        = 'Lagana.Consulting.Toolkit.Analysis.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d'
    Author            = 'Lagana Consulting'
    CompanyName       = 'Lagana Consulting'
    Copyright         = '(c) Lagana Consulting. All rights reserved.'
    Description       = 'Client-side analysis and reporting toolkit for AD assessments (PowerShell 7.0+).'
    PowerShellVersion = '7.0'

    RequiredModules   = @('Lagana.Consulting.Toolkit')

    FunctionsToExport = @(
        # Schema and safe exports
        'Export-LcCsvSafe',
        'Get-LcSchemaDefinitions',
        'Export-LcSchemas',
        'Write-LcSchemaCsv',

        # Reports
        'New-LcAssessmentReport',
        'New-LcComprehensiveAssessmentReport',
        'New-LcMigrationPlanningReport',
        'New-LcMigrationLoeExcel',
        'New-LcEnvironmentComparisonReport',
        'New-LcMigrationReadinessChecklist',

        # Discovery orchestration
        'Invoke-LcDiscoveryComparison',
        'Invoke-LcDiscoveryAnalysis'
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
