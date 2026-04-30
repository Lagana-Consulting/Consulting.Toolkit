Set-StrictMode -Version Latest

$PublicPath = Join-Path $PSScriptRoot 'Public'
$PrivatePath = Join-Path $PSScriptRoot 'Private'

Get-ChildItem -Path $PrivatePath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

Get-ChildItem -Path $PublicPath -Filter *.ps1 -File -ErrorAction SilentlyContinue |
Where-Object { $_.Name -notin @('run-planning.ps1') } |
ForEach-Object {
    . $_.FullName
}

Export-ModuleMember -Function @(
    'Test-AdMigrationPrerequisites',
    'New-AdMigrationIncludeFile',
    'New-AdMigrationExcludeFile',
    'New-AdMigrationPlanningPackage'
)
