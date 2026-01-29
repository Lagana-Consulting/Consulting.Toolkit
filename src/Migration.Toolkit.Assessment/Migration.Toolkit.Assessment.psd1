@{
    RootModule        = 'Migration.Toolkit.Assessment.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '9bb6a36b-4f19-4f1a-8ff1-6d1e2a9b1ed6'
    Author            = 'Quest'
    CompanyName       = 'Quest'
    Copyright         = '(c) 2026 Quest. All rights reserved.'
    Description       = 'Assessment module for AD, Entra, and M365 reporting using Word templates.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Invoke-AdAssessment',
        'Add-AdSimpleSummaryTable',
        'Add-AdRawTableFromCsv',
        'Add-AdPivotTableFromCsv',
        'Add-AdUserStatsSummary',
        'Add-AdDeviceSummary',
        'Add-AdOuStructureSummary',
        'Add-AzEntraUserSummary',
        'Add-AzM365GroupSummary',
        'Add-AzMailboxSummary',
        'Add-AzOneDriveSummary',
        'Add-AzTeamsActivitySummary',
        'Add-AzSharePointSummary',
        'Add-AdSingleRowSummaryFromCsv',
        'Add-AdCountRowsSummary',
        'Add-AzEntraGuestDomainSummary',
        'Add-AdDomainDiscoveryTable'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('ActiveDirectory', 'Entra', 'M365', 'Assessment', 'Word', 'Reporting')
            ProjectUri   = ''
            LicenseUri   = ''
            ReleaseNotes = 'Initial scaffold.'
        }
    }
}
