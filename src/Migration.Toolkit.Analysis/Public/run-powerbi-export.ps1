<#
.SYNOPSIS
Runs Export-AdPowerBiDataset as a standalone script.

.DESCRIPTION
Imports the local Migration.Toolkit.Analysis module and exports curated CSV tables
for Power BI Desktop from one or more Consulting.Toolkit.Discovery run folders.

.PARAMETER RunRoot
One or more discovery run roots to include in the exported dataset.

.PARAMETER WorkspaceRoot
Optional analysis workspace root produced by Invoke-AdDiscoveryAnalysis.

.PARAMETER OutputRoot
Folder where curated CSV tables will be written.

.EXAMPLE
& .\run-powerbi-export.ps1 `
  -RunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -OutputRoot "F:\Shared\PowerBI\ADDataset"

.EXAMPLE
& .\run-powerbi-export.ps1 `
  -RunRoot @(
    "F:\Shared\AD_source_20260423-082040",
    "F:\Shared\AD_target_20260423-090000"
  ) `
  -WorkspaceRoot "F:\Shared\AnalysisWorkspace" `
  -OutputRoot "F:\Shared\PowerBI\ADDataset"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$RunRoot,

    [string]$WorkspaceRoot,

    [Parameter(Mandatory)]
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $moduleRoot 'Migration.Toolkit.Analysis.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
    throw "Module manifest not found: $moduleManifest"
}

Import-Module $moduleManifest -Force

Write-Host "Exporting Power BI dataset..." -ForegroundColor Cyan
Write-Host "  Output: $OutputRoot" -ForegroundColor Gray

$params = @{
    RunRoot    = $RunRoot
    OutputRoot = $OutputRoot
}

if ($PSBoundParameters.ContainsKey('WorkspaceRoot') -and -not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $params.WorkspaceRoot = $WorkspaceRoot
    Write-Host "  Workspace: $WorkspaceRoot" -ForegroundColor Gray
}

$result = Export-AdPowerBiDataset @params

Write-Host ""
Write-Host "Power BI export complete." -ForegroundColor Green
Write-Host "  Manifest: $($result.ManifestPath)" -ForegroundColor Yellow
Write-Host "  Tables:   $($result.TablesWritten)" -ForegroundColor Yellow

$result.Tables | ForEach-Object {
    Write-Host ("  {0}: {1}" -f $_.Name, $_.Path) -ForegroundColor DarkYellow
}

$result
