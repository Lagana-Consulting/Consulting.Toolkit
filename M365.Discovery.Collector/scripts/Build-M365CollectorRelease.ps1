<#
.SYNOPSIS
Builds and packages a customer-ready M365 Discovery Collector release zip.

.DESCRIPTION
Publishes Collector.Console and Collector.App, stages required scripts/config/docs,
and creates a timestamped zip for handoff.

.EXAMPLE
pwsh ./scripts/Build-M365CollectorRelease.ps1

.EXAMPLE
pwsh ./scripts/Build-M365CollectorRelease.ps1 -Configuration Debug -SkipGui
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [Parameter()]
    [string]$OutputRoot = (Join-Path (Join-Path $PSScriptRoot "..") "releases"),

    [Parameter()]
    [string]$PackageName = ("M365.Discovery.Collector_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")),

    [Parameter()]
    [switch]$SkipGui
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

$collectorRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $collectorRoot ".."))
$resolvedOutputRoot = Resolve-AbsolutePath -PathValue $OutputRoot

$stagingRoot = Join-Path $resolvedOutputRoot $PackageName
$zipPath = Join-Path $resolvedOutputRoot ("{0}.zip" -f $PackageName)

$consoleProject = Join-Path $collectorRoot "Collector.Console/Collector.Console.csproj"
$appProject = Join-Path $collectorRoot "Collector.App/Collector.App.csproj"
$collectorReadme = Join-Path $collectorRoot "README.md"
$customerGuide = Join-Path $repoRoot "docs/CUSTOMER_RUN_GUIDE.md"

Write-Host "== Build M365 Collector Release ==" -ForegroundColor Cyan
Write-Host "Collector root: $collectorRoot"
Write-Host "Output root:    $resolvedOutputRoot"
Write-Host "Package:        $PackageName"
Write-Host "Configuration:  $Configuration"
Write-Host "Skip GUI:       $($SkipGui.IsPresent)"
Write-Host ""

New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null

if (Test-Path $stagingRoot) {
    Remove-Item -Path $stagingRoot -Recurse -Force
}
if (Test-Path $zipPath) {
    Remove-Item -Path $zipPath -Force
}

New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "bin") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "scripts") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingRoot "docs") -Force | Out-Null

Write-Host "Publishing Collector.Console..." -ForegroundColor Gray
$consolePublishDir = Join-Path $stagingRoot "bin/Collector.Console"
& dotnet publish $consoleProject -c $Configuration -o $consolePublishDir
if ($LASTEXITCODE -ne 0) {
    throw "Collector.Console publish failed with exit code $LASTEXITCODE."
}

if (-not $SkipGui) {
    Write-Host "Publishing Collector.App..." -ForegroundColor Gray
    $appPublishDir = Join-Path $stagingRoot "bin/Collector.App"
    & dotnet publish $appProject -c $Configuration -o $appPublishDir
    if ($LASTEXITCODE -ne 0) {
        throw "Collector.App publish failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Staging scripts and docs..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $collectorRoot "scripts/run-collector.ps1") -Destination (Join-Path $stagingRoot "scripts/run-collector.ps1") -Force
Copy-Item -Path (Join-Path $collectorRoot "scripts/Setup-M365DiscoveryApp.ps1") -Destination (Join-Path $stagingRoot "scripts/Setup-M365DiscoveryApp.ps1") -Force
Copy-Item -Path (Join-Path $collectorRoot "scripts/collector-config.template.json") -Destination (Join-Path $stagingRoot "scripts/collector-config.template.json") -Force
Copy-Item -Path $collectorReadme -Destination (Join-Path $stagingRoot "README.md") -Force

if (Test-Path $customerGuide) {
    Copy-Item -Path $customerGuide -Destination (Join-Path $stagingRoot "docs/CUSTOMER_RUN_GUIDE.md") -Force
}

$manifestPath = Join-Path $stagingRoot "PACKAGE_MANIFEST.txt"
$manifestLines = @(
    "M365 Discovery Collector Release Package",
    ("GeneratedUtc={0}" -f ([DateTime]::UtcNow.ToString("o"))),
    ("Configuration={0}" -f $Configuration),
    ("IncludeGui={0}" -f (-not $SkipGui.IsPresent)),
    ("PackageName={0}" -f $PackageName),
    "",
    "Contents:",
    "  bin/Collector.Console/",
    "  bin/Collector.App/ (unless -SkipGui)",
    "  scripts/run-collector.ps1",
    "  scripts/Setup-M365DiscoveryApp.ps1",
    "  scripts/collector-config.template.json",
    "  docs/CUSTOMER_RUN_GUIDE.md",
    "  README.md"
)
$manifestLines | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host "Creating zip archive..." -ForegroundColor Gray
Compress-Archive -Path (Join-Path $stagingRoot "*") -DestinationPath $zipPath -Force

$zipHash = Get-FileHash -Path $zipPath -Algorithm SHA256
$hashPath = Join-Path $resolvedOutputRoot ("{0}.sha256.txt" -f $PackageName)
("{0}  {1}" -f $zipHash.Hash, [System.IO.Path]::GetFileName($zipPath)) | Set-Content -Path $hashPath -Encoding UTF8

Write-Host ""
Write-Host "Release package created." -ForegroundColor Green
Write-Host "Staging folder: $stagingRoot"
Write-Host "Zip file:       $zipPath"
Write-Host "SHA256 file:    $hashPath"
