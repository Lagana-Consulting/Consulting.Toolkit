<#
.SYNOPSIS
Build an internal migration planning package from discovery output.

.EXAMPLE
& ".\run-planning.ps1" `
  -SourceRunRoot "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723" `
  -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
  -IncludeNonRoutableUpnUsers `
  -CreateCustomerPackage `
  -ZipCustomerPackage `
  -OutputRoot "F:\Versetal\MigrationPlanning"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$SourceRunRoot,

    [string]$TargetRunRoot,

    [string]$OutputRoot,

    [string]$CustomerName = 'Organization',

    [string]$PlanningConfigPath,

    [switch]$IncludeNonRoutableUpnUsers,

    [switch]$CreateCustomerPackage,

    [switch]$ZipCustomerPackage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $moduleRoot 'Migration.Toolkit.Planning.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
    throw "Module manifest not found: $moduleManifest"
}

Import-Module $moduleManifest -Force

$params = @{
    SourceRunRoot = $SourceRunRoot
    CustomerName  = $CustomerName
}

if ($PSBoundParameters.ContainsKey('TargetRunRoot') -and -not [string]::IsNullOrWhiteSpace($TargetRunRoot)) {
    $params.TargetRunRoot = $TargetRunRoot
}
if ($PSBoundParameters.ContainsKey('OutputRoot') -and -not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $params.OutputRoot = $OutputRoot
}
if ($PSBoundParameters.ContainsKey('PlanningConfigPath') -and -not [string]::IsNullOrWhiteSpace($PlanningConfigPath)) {
    $params.PlanningConfigPath = $PlanningConfigPath
}
if ($IncludeNonRoutableUpnUsers) {
    $params.IncludeNonRoutableUpnUsers = $true
}
if ($CreateCustomerPackage) {
    $params.CreateCustomerPackage = $true
}
if ($ZipCustomerPackage) {
    $params.ZipCustomerPackage = $true
}

$result = New-AdMigrationPlanningPackage @params

Write-Host ""
Write-Host "Migration planning package complete." -ForegroundColor Green
Write-Host "  Output: $($result.OutputRoot)" -ForegroundColor Yellow
Write-Host "  Manifest: $($result.ManifestPath)" -ForegroundColor Yellow
Write-Host "  README: $($result.ReadmePath)" -ForegroundColor Yellow
if ($result.PrerequisiteCsv) {
    Write-Host "  Prerequisites CSV: $($result.PrerequisiteCsv)" -ForegroundColor Yellow
}
Write-Host "  Include Non-Routable UPN Users: $([bool]$IncludeNonRoutableUpnUsers)" -ForegroundColor Yellow
if ($result.CustomerPackageRoot) {
    Write-Host "  Customer Package: $($result.CustomerPackageRoot)" -ForegroundColor Yellow
}
if ($result.CustomerIndexPath) {
    Write-Host "  Customer Index: $($result.CustomerIndexPath)" -ForegroundColor Yellow
}
if ($result.CustomerChecklistPath) {
    Write-Host "  Customer Action Checklist: $($result.CustomerChecklistPath)" -ForegroundColor Yellow
}
if ($result.CustomerZipPath) {
    Write-Host "  Customer ZIP: $($result.CustomerZipPath)" -ForegroundColor Yellow
}

$result
