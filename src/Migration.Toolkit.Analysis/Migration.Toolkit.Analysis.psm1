Set-StrictMode -Version Latest

$PublicPath = Join-Path $PSScriptRoot 'Public'
$PrivatePath = Join-Path $PSScriptRoot 'Private'

# Dot-source Private first
Get-ChildItem -Path $PrivatePath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Dot-source Public (skip helper scripts)
Get-ChildItem -Path $PublicPath -Filter *.ps1 -File -ErrorAction SilentlyContinue |
Where-Object { $_.Name -notin @('run-discoveryanalysis.ps1', 'run-analysis.ps1', 'run-powerbi-export.ps1', 'run-assessment-package.ps1') } |
ForEach-Object {
    . $_.FullName
}

# Export only public functions
Export-ModuleMember -Function @(
    # Schema and safe exports
    'Export-AdCsvSafe',
    'Export-AdPowerBiDataset',
    'Get-AdSchemaDefinitions',

    # Reports
    'New-AdAssessmentReport',
    'New-AdAssessmentPackage',
    'New-AdComprehensiveAssessmentReport',
    'New-AdMigrationPlanningReport',
    'New-AdEnvironmentComparisonReport',
    'New-AdMigrationReadinessChecklist',
    'New-AdEnvironmentSummaryDocument',

    # Discovery orchestration
    'Invoke-AdDiscoveryComparison',
    'Invoke-AdDiscoveryAnalysis',
    'Invoke-AdCrossForestDuplicateCheck'
)
