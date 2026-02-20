<#
.SYNOPSIS
Runs smoke checks for M365 Discovery Collector CLI.

.DESCRIPTION
Validates key runtime behaviors used by CI:
- build succeeds
- --help works
- --list-workloads works
- role boundary blocks bootstrap-admin runtime path
- self-check passes for operator with a minimal local config

.EXAMPLE
pwsh ./scripts/Test-M365CollectorSmoke.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [Parameter()]
    [string]$ProjectPath,

    [Parameter()]
    [string]$OutputRoot
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

function Invoke-CollectorCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$CollectorArgs
    )

    $dotnetArgs = @(
        "run",
        "--project", $script:ResolvedProjectPath,
        "--configuration", $script:Configuration,
        "--no-build",
        "--"
    ) + $CollectorArgs

    Write-Host ("[{0}] dotnet {1}" -f $Name, ($dotnetArgs -join " ")) -ForegroundColor Gray

    $lines = & dotnet @dotnetArgs 2>&1
    $exitCode = $LASTEXITCODE
    $output = ($lines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    $logPath = Join-Path $script:LogsPath ("{0}.log" -f $Name)
    $output | Set-Content -Path $logPath -Encoding UTF8

    return [pscustomobject]@{
        Name     = $Name
        ExitCode = [int]$exitCode
        Output   = $output
        LogPath  = $logPath
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$collectorRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $collectorRoot "Collector.Console/Collector.Console.csproj"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $collectorRoot "artifacts/smoke"
}

$script:ResolvedProjectPath = Resolve-AbsolutePath -PathValue $ProjectPath
$script:Configuration = $Configuration
$resolvedOutputRoot = Resolve-AbsolutePath -PathValue $OutputRoot
$script:LogsPath = Join-Path $resolvedOutputRoot "logs"

if (-not (Test-Path -Path $script:ResolvedProjectPath -PathType Leaf)) {
    throw "Collector project not found: $script:ResolvedProjectPath"
}

New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $script:LogsPath -Force | Out-Null

$configPath = Join-Path $resolvedOutputRoot "selfcheck-auth-config.json"
@'
{
  "ClientId": "00000000-0000-0000-0000-000000000000",
  "TenantId": "contoso.onmicrosoft.com",
  "CertificateThumbprint": "00112233445566778899AABBCCDDEEFF00112233",
  "AllowClientSecretFallback": false,
  "Mode": "AppOnly",
  "DelegatedScopes": []
}
'@ | Set-Content -Path $configPath -Encoding UTF8

Write-Host "== M365 Collector Smoke Checks ==" -ForegroundColor Cyan
Write-Host "Project:      $script:ResolvedProjectPath"
Write-Host "Configuration:$Configuration"
Write-Host "Output root:  $resolvedOutputRoot"
Write-Host "Config file:  $configPath"
Write-Host ""

Write-Host "Building Collector.Console..." -ForegroundColor Gray
& dotnet build $script:ResolvedProjectPath --configuration $Configuration
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
}
Write-Host ""

$helpResult = Invoke-CollectorCommand -Name "01-help" -CollectorArgs @("--help", "--no-banner")
if ($helpResult.ExitCode -ne 0) {
    throw "--help failed. See $($helpResult.LogPath)"
}
if ($helpResult.Output -notmatch "--self-check" -or $helpResult.Output -notmatch "--list-workloads") {
    throw "--help output missing expected options. See $($helpResult.LogPath)"
}

$listResult = Invoke-CollectorCommand -Name "02-list-workloads" -CollectorArgs @("--list-workloads", "--no-banner")
if ($listResult.ExitCode -ne 0) {
    throw "--list-workloads failed. See $($listResult.LogPath)"
}
if ($listResult.Output -notmatch "Available workloads:" -or $listResult.Output -notmatch "entra\.users") {
    throw "--list-workloads output missing expected content. See $($listResult.LogPath)"
}

$boundaryResult = Invoke-CollectorCommand -Name "03-role-boundary" -CollectorArgs @(
    "--role", "bootstrap-admin",
    "--self-check",
    "--config", $configPath,
    "--workloads", "default",
    "--output-root", $resolvedOutputRoot
)
if ($boundaryResult.ExitCode -eq 0) {
    throw "Role boundary check expected failure but returned success. See $($boundaryResult.LogPath)"
}
if ($boundaryResult.Output -notmatch "Role boundary") {
    throw "Role boundary check failed for unexpected reason. See $($boundaryResult.LogPath)"
}

$selfCheckResult = Invoke-CollectorCommand -Name "04-self-check-pass" -CollectorArgs @(
    "--role", "operator",
    "--self-check",
    "--config", $configPath,
    "--workloads", "default",
    "--output-root", $resolvedOutputRoot
)
if ($selfCheckResult.ExitCode -ne 0) {
    throw "Operator self-check failed. See $($selfCheckResult.LogPath)"
}
if ($selfCheckResult.Output -notmatch "Self-check completed: PASS") {
    throw "Operator self-check output did not report PASS. See $($selfCheckResult.LogPath)"
}

Write-Host ""
Write-Host "Smoke checks passed." -ForegroundColor Green
Write-Host "Logs: $script:LogsPath"
