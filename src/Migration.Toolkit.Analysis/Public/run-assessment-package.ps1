<#
.SYNOPSIS
Builds the HTML-first AD assessment package plus structured data bundle.

.DESCRIPTION
Runs the primary assessment workflow for one or more source discovery runs and
produces:
- HTML assessment reports
- Optional comprehensive HTML reports
- Optional source-vs-target comparison and readiness reports
- Optional structured CSV dataset for downstream SQL / Power BI work
- Optional shared analysis workspace
- Package landing page and manifest
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$SourceRunRoot,

    [string]$TargetRunRoot,

    [string]$OutputRoot,

    [string]$WorkspaceRoot,

    [string]$CustomerName = 'Organization',

    [string]$ExecutiveSummaryConfigPath,

    [switch]$IncludeComprehensiveReport,

    [switch]$SkipStructuredData,

    [switch]$CreateCustomerPackage,

    [switch]$ZipCustomerPackage,

    [switch]$SkipWorkspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $moduleRoot 'Migration.Toolkit.Analysis.psd1'
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
if ($PSBoundParameters.ContainsKey('WorkspaceRoot') -and -not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $params.WorkspaceRoot = $WorkspaceRoot
}
if ($PSBoundParameters.ContainsKey('ExecutiveSummaryConfigPath') -and -not [string]::IsNullOrWhiteSpace($ExecutiveSummaryConfigPath)) {
    $params.ExecutiveSummaryConfigPath = $ExecutiveSummaryConfigPath
}
if ($IncludeComprehensiveReport) {
    $params.IncludeComprehensiveReport = $true
}
if ($SkipStructuredData) {
    $params.SkipStructuredData = $true
}
if ($CreateCustomerPackage) {
    $params.CreateCustomerPackage = $true
}
if ($ZipCustomerPackage) {
    $params.ZipCustomerPackage = $true
}
if ($SkipWorkspace) {
    $params.SkipWorkspace = $true
}

$result = New-AdAssessmentPackage @params

Write-Host ""
Write-Host "Assessment package complete." -ForegroundColor Green
Write-Host "  Index: $($result.IndexPath)" -ForegroundColor Yellow
Write-Host "  Manifest: $($result.ManifestPath)" -ForegroundColor Yellow
if ($result.StructuredDataRoot) {
    Write-Host "  Structured Data: $($result.StructuredDataRoot)" -ForegroundColor Yellow
}
if ($result.WorkspaceRoot) {
    Write-Host "  Workspace: $($result.WorkspaceRoot)" -ForegroundColor Yellow
}
if ($result.CustomerPackageRoot) {
    Write-Host "  Customer Package: $($result.CustomerPackageRoot)" -ForegroundColor Yellow
    if ($result.CustomerIndexPath) {
        Write-Host "  Customer Index: $($result.CustomerIndexPath)" -ForegroundColor Yellow
    }
    if ($result.CustomerReadmePath) {
        Write-Host "  Customer README: $($result.CustomerReadmePath)" -ForegroundColor Yellow
    }
    if ($result.CustomerZipPath) {
        Write-Host "  Customer ZIP: $($result.CustomerZipPath)" -ForegroundColor Yellow
    }
}

$result
