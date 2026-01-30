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
    # Main orchestration
    'Invoke-AdAssessment',
    'Invoke-ADOnlyAssessment',
    'Invoke-AZOnlyAssessment',
    'Invoke-FullAssessment',
    'Invoke-ADAssessmentAutomation',

    # Base table builders
    'Add-AdSimpleSummaryTable',
    'Add-AdRawTableFromCsv',
    'Add-AdPivotTableFromCsv',

    # AD-specific tables
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
    'Add-AdDomainDiscoveryTable',

    # Entra-specific tables
    'Add-AzEntraUserSummary',
    'Add-AzEntraGuestDomainSummary',

    # M365-specific tables
    'Add-AzM365GroupSummary',
    'Add-AzMailboxSummary',
    'Add-AzOneDriveSummary',
    'Add-AzTeamsActivitySummary',
    'Add-AzSharePointSummary',

    # Utility builders
    'Add-AdSingleRowSummaryFromCsv',
    'Add-AdCountRowsSummary'
)
