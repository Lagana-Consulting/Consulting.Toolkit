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
        'Invoke-ADOnlyAssessment',
        'Invoke-AZOnlyAssessment',
        'Invoke-FullAssessment',
        'Invoke-ADAssessmentAutomation',
        'Add-AdRawTableFromCsv',
        'Add-AdPivotTableFromCsv',
        'Add-AdUserStatsSummary',
        'Add-AdDeviceSummary',
        'Add-AdWorkstationSummary',
        'Add-AdServerSummary',
        'Add-AdOuStructureSummary',
        'Add-AdForestSummary',
        'Add-AdTrustInformation',
        'Add-AdDomainInformation',
        'Add-AdDomainControllers',
        'Add-AdPasswordPolicies',
        'Add-AdFineGrainPasswordPolicies',
        'Add-AdGPOSummary',
        'Add-AdGroupStatsSummary',
        'Add-AdContactsStatsSummary',
        'Add-AdPublishedPrinters',
        'Add-AdOUDepthSummary',
        'Add-AzEntraUserSummary',
        'Add-AzM365GroupSummary',
        'Add-AzMailboxSummary',
        'Add-AzOneDriveSummary',
        'Add-AzTeamsActivitySummary',
        'Add-AzSharePointSummary',
        'Add-AdSingleRowSummaryFromCsv',
        'Add-AdCountRowsSummary',
        'Add-AzEntraGuestDomainSummary',
        'Add-AdDomainDiscoveryTable',
        'Add-AdEmptyGroupsTable',
        'Add-AdServiceAccountsTable',
        'Add-AdSpnsTable',
        'Add-AdPrivilegedAccountsTable',
        'Add-AdForestRiskSummary',
        'Add-AdForestRiskFlags',
        'Add-AdDomainRiskSummary',
        'Add-AdDomainRiskFlags'
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
