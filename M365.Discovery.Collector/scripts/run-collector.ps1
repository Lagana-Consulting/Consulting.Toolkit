<#
.SYNOPSIS
Runs M365 Discovery Collector CLI with standard operator parameters and log capture.

.DESCRIPTION
Builds (optional) and runs Collector.Console with role boundary, workload selection,
config path, output root, run name, and preflight-only mode.

Designed for customer/operator execution from a cloned repo or packaged drop.

.EXAMPLE
pwsh ./scripts/run-collector.ps1 -PreflightOnly

.EXAMPLE
pwsh ./scripts/run-collector.ps1 -ConfigPath "$env:APPDATA\M365DiscoveryCollector\config.json" -Workloads all

.EXAMPLE
pwsh ./scripts/run-collector.ps1 -SelfCheck -PreflightOnly

.EXAMPLE
pwsh ./scripts/run-collector.ps1 -Workloads "entra.roles,entra.conditionalAccess,entra.authMethods,hybrid.aadConnectConfig"
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("operator", "bootstrap-admin")]
    [string]$Role = "operator",

    [Parameter()]
    [string]$ConfigPath = "collector-config.json",

    [Parameter()]
    [string]$Workloads = "default",

    [Parameter()]
    [string]$OutputRoot = (Join-Path (Get-Location) "CollectorOutput"),

    [Parameter()]
    [string]$RunName = ("Discovery_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")),

    [Parameter()]
    [switch]$PreflightOnly,

    [Parameter()]
    [switch]$SelfCheck,

    [Parameter()]
    [switch]$NoBuild,

    [Parameter()]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Debug",

    [Parameter()]
    [string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-PathSafe {
    param([Parameter(Mandatory)][string]$PathValue)

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $PathValue))
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = Join-Path $repoRoot "Collector.Console/Collector.Console.csproj"
}

$resolvedProjectPath = Resolve-PathSafe -PathValue $ProjectPath
if (-not (Test-Path -Path $resolvedProjectPath -PathType Leaf)) {
    throw "Collector console project not found: $resolvedProjectPath"
}

$resolvedOutputRoot = Resolve-PathSafe -PathValue $OutputRoot
New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null

# Keep relative config path relative to current directory for expected CLI semantics.
$configArgument = $ConfigPath

$logFile = Join-Path $resolvedOutputRoot ("{0}.log" -f $RunName)

Write-Host "== M365 Discovery Collector Runner ==" -ForegroundColor Cyan
Write-Host "Role:         $Role"
Write-Host "Project:      $resolvedProjectPath"
Write-Host "Config:       $configArgument"
Write-Host "Workloads:    $Workloads"
Write-Host "Output Root:  $resolvedOutputRoot"
Write-Host "Run Name:     $RunName"
Write-Host "Preflight:    $($PreflightOnly.IsPresent)"
Write-Host "SelfCheck:    $($SelfCheck.IsPresent)"
Write-Host "Log File:     $logFile"
Write-Host ""

if (-not $NoBuild) {
    Write-Host "Building Collector.Console ($Configuration)..." -ForegroundColor Gray
    & dotnet build $resolvedProjectPath --configuration $Configuration
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE."
    }
    Write-Host ""
}

function Invoke-CollectorRun {
    param(
        [Parameter(Mandatory)][string[]]$CollectorArgs,
        [Parameter()][bool]$AppendLog = $false,
        [Parameter(Mandatory)][string]$LogPath
    )

    $dotnetArgs = @(
        "run",
        "--project", $resolvedProjectPath,
        "--configuration", $Configuration,
        "--"
    ) + $CollectorArgs

    Write-Host ("dotnet {0}" -f ($dotnetArgs -join " "))
    Write-Host ""

    if ($AppendLog) {
        & dotnet @dotnetArgs 2>&1 | Tee-Object -FilePath $LogPath -Append | Out-Host
    } else {
        & dotnet @dotnetArgs 2>&1 | Tee-Object -FilePath $LogPath | Out-Host
    }

    return [int]$LASTEXITCODE
}

$collectorArgs = @(
    "--role", $Role,
    "--config", $configArgument,
    "--workloads", $Workloads,
    "--output-root", $resolvedOutputRoot,
    "--run-name", $RunName
)

if ($PreflightOnly) {
    $collectorArgs += "--preflight-only"
}

if ($SelfCheck) {
    Write-Host "Running self-check before collector run..." -ForegroundColor Gray
    $selfCheckArgs = @(
        "--role", $Role,
        "--config", $configArgument,
        "--workloads", $Workloads,
        "--output-root", $resolvedOutputRoot,
        "--self-check"
    )
    $selfCheckExit = Invoke-CollectorRun -CollectorArgs $selfCheckArgs -LogPath $logFile
    if ($selfCheckExit -ne 0) {
        Write-Host "Self-check failed with exit code $selfCheckExit. Aborting run." -ForegroundColor Red
        Write-Host "Execution log: $logFile"
        exit $selfCheckExit
    }
    Write-Host "Self-check passed." -ForegroundColor Green
    Write-Host ""
}

Write-Host "Running collector..." -ForegroundColor Gray
$exitCode = Invoke-CollectorRun -CollectorArgs $collectorArgs -AppendLog:$SelfCheck.IsPresent -LogPath $logFile

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "Collector run completed successfully." -ForegroundColor Green
    Write-Host "Run output root: $resolvedOutputRoot"
    Write-Host "Execution log:   $logFile"
} else {
    Write-Host "Collector run failed with exit code $exitCode." -ForegroundColor Red
    Write-Host "Execution log: $logFile"
}

exit $exitCode
