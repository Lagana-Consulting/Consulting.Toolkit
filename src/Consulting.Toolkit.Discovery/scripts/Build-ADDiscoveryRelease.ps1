<#
.SYNOPSIS
Builds a customer-ready release package for Consulting.Toolkit.Discovery.

.DESCRIPTION
Stages module files, operator scripts, and customer run guide, then creates a zip
and SHA256 checksum file.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-ADDiscoveryRelease.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputRoot = "",

    [Parameter()]
    [string]$PackageName = ("Consulting.Toolkit.Discovery_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-AbsolutePath {
    param([Parameter(Mandatory)][string]$PathValue)

    if (-not [System.IO.Path]::IsPathRooted($PathValue)) {
        $PathValue = Join-Path (Get-Location).Path $PathValue
    }

    return [System.IO.Path]::GetFullPath($PathValue)
}

$moduleRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $moduleRoot "..\.."))

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $moduleRoot "releases"
}

$resolvedOutputRoot = Resolve-AbsolutePath -PathValue $OutputRoot
$stagingRoot = Join-Path $resolvedOutputRoot $PackageName
$zipPath = Join-Path $resolvedOutputRoot ("{0}.zip" -f $PackageName)
$hashPath = Join-Path $resolvedOutputRoot ("{0}.sha256.txt" -f $PackageName)

Write-Host "== Build AD Discovery Release ==" -ForegroundColor Cyan
Write-Host ("Module Root: {0}" -f $moduleRoot)
Write-Host ("OutputRoot:  {0}" -f $resolvedOutputRoot)
Write-Host ("Package:     {0}" -f $PackageName)
Write-Host ""

New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null

if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if (Test-Path -LiteralPath $hashPath) { Remove-Item -LiteralPath $hashPath -Force }

New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "module\Consulting.Toolkit.Discovery") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "scripts") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "docs") -Force | Out-Null

$moduleDest = Join-Path $stagingRoot "module\Consulting.Toolkit.Discovery"

Write-Host "Staging module..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $moduleRoot "Consulting.Toolkit.Discovery.psd1") -Destination (Join-Path $moduleDest "Consulting.Toolkit.Discovery.psd1") -Force
Copy-Item -Path (Join-Path $moduleRoot "Consulting.Toolkit.Discovery.psm1") -Destination (Join-Path $moduleDest "Consulting.Toolkit.Discovery.psm1") -Force
Copy-Item -Path (Join-Path $moduleRoot "Public") -Destination (Join-Path $moduleDest "Public") -Recurse -Force
Copy-Item -Path (Join-Path $moduleRoot "Private") -Destination (Join-Path $moduleDest "Private") -Recurse -Force
Copy-Item -Path (Join-Path $moduleRoot "Indicator_Discovery_Matrix.csv") -Destination (Join-Path $moduleDest "Indicator_Discovery_Matrix.csv") -Force
Copy-Item -Path (Join-Path $moduleRoot "SecurityIndicators.json") -Destination (Join-Path $moduleDest "SecurityIndicators.json") -Force

Write-Host "Staging scripts..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $moduleRoot "scripts\run-ad-discovery.ps1") -Destination (Join-Path $stagingRoot "scripts\run-ad-discovery.ps1") -Force
Copy-Item -Path (Join-Path $moduleRoot "scripts\Test-ADDiscoverySmoke.ps1") -Destination (Join-Path $stagingRoot "scripts\Test-ADDiscoverySmoke.ps1") -Force
Copy-Item -Path (Join-Path $moduleRoot "scripts\ad-discovery-run-settings.template.json") -Destination (Join-Path $stagingRoot "scripts\ad-discovery-run-settings.template.json") -Force

$guidePath = Join-Path $repoRoot "docs\AD_CUSTOMER_RUN_GUIDE.md"
if (Test-Path -LiteralPath $guidePath) {
    Copy-Item -Path $guidePath -Destination (Join-Path $stagingRoot "docs\AD_CUSTOMER_RUN_GUIDE.md") -Force
}

$manifestPath = Join-Path $stagingRoot "PACKAGE_MANIFEST.txt"
@(
    "Consulting.Toolkit.Discovery Release Package"
    ("GeneratedUtc={0}" -f [DateTime]::UtcNow.ToString("o"))
    ("PackageName={0}" -f $PackageName)
    ""
    "Contents:"
    "  module/Consulting.Toolkit.Discovery/"
    "  scripts/run-ad-discovery.ps1"
    "  scripts/Test-ADDiscoverySmoke.ps1"
    "  scripts/ad-discovery-run-settings.template.json"
    "  docs/AD_CUSTOMER_RUN_GUIDE.md"
) | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host "Creating zip archive..." -ForegroundColor Gray
Compress-Archive -Path (Join-Path $stagingRoot "*") -DestinationPath $zipPath -Force

$zipHash = Get-FileHash -Path $zipPath -Algorithm SHA256
("{0}  {1}" -f $zipHash.Hash, [System.IO.Path]::GetFileName($zipPath)) | Set-Content -Path $hashPath -Encoding UTF8

Write-Host ""
Write-Host "[OK] Release package created." -ForegroundColor Green
Write-Host ("Staging: {0}" -f $stagingRoot)
Write-Host ("Zip:     {0}" -f $zipPath)
Write-Host ("SHA256:  {0}" -f $hashPath)
