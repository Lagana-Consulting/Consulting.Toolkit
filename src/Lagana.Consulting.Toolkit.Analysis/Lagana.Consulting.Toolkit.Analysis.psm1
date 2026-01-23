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
