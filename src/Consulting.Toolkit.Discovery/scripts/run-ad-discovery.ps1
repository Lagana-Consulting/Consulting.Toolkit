<#
.SYNOPSIS
Runs Consulting.Toolkit.Discovery AD collection with preflight validation and run logging.

.DESCRIPTION
Imports the local module path, validates prerequisites, and executes Invoke-AdDiscoveryExport.
Designed for operator execution on customer hosts.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-ad-discovery.ps1 -PreflightOnly

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-ad-discovery.ps1 -Environment Source -OutputRoot C:\Discovery -IncludeSecurity
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$Environment = "Source",

    [Parameter()]
    [string]$OutputRoot = "C:\Discovery",

    [Parameter()]
    [string]$CustomerName = "",

    [Parameter()]
    [string]$Server = "",

    [Parameter()]
    [switch]$IncludeSecurity,

    [Parameter()]
    [switch]$PreflightOnly,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [string]$ModulePath
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

function Test-IsWritablePath {
    param([Parameter(Mandatory)][string]$PathValue)

    if (-not (Test-Path -LiteralPath $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }

    $probe = Join-Path $PathValue (".ad-discovery-write-test-{0}.tmp" -f [guid]::NewGuid().ToString("N"))
    Set-Content -Path $probe -Value "ok" -Encoding UTF8
    Remove-Item -LiteralPath $probe -Force
}

function Get-JsonConfig {
    param([Parameter(Mandatory)][string]$PathValue)

    if (-not (Test-Path -LiteralPath $PathValue -PathType Leaf)) {
        throw "Config file not found: $PathValue"
    }

    return (Get-Content -LiteralPath $PathValue -Raw | ConvertFrom-Json)
}

function Try-SetFromConfig {
    param(
        [Parameter(Mandatory)][object]$ConfigObject,
        [Parameter(Mandatory)][string]$PropertyName,
        [Parameter(Mandatory)][scriptblock]$Setter
    )

    if ($null -eq $ConfigObject) {
        return
    }

    if ($ConfigObject.PSObject.Properties.Name -contains $PropertyName) {
        $value = $ConfigObject.$PropertyName
        & $Setter $value
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $moduleRoot "Consulting.Toolkit.Discovery.psd1"
}

if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $resolvedConfigPath = Resolve-AbsolutePath -PathValue $ConfigPath
    $cfg = Get-JsonConfig -PathValue $resolvedConfigPath

    if (-not $PSBoundParameters.ContainsKey("Environment")) {
        Try-SetFromConfig -ConfigObject $cfg -PropertyName "Environment" -Setter { param($v) if ($null -ne $v) { $script:Environment = [string]$v } }
    }
    if (-not $PSBoundParameters.ContainsKey("OutputRoot")) {
        Try-SetFromConfig -ConfigObject $cfg -PropertyName "OutputRoot" -Setter { param($v) if ($null -ne $v) { $script:OutputRoot = [string]$v } }
    }
    if (-not $PSBoundParameters.ContainsKey("CustomerName")) {
        Try-SetFromConfig -ConfigObject $cfg -PropertyName "CustomerName" -Setter { param($v) if ($null -ne $v) { $script:CustomerName = [string]$v } }
    }
    if (-not $PSBoundParameters.ContainsKey("Server")) {
        Try-SetFromConfig -ConfigObject $cfg -PropertyName "Server" -Setter { param($v) if ($null -ne $v) { $script:Server = [string]$v } }
    }
    if (-not $PSBoundParameters.ContainsKey("IncludeSecurity")) {
        Try-SetFromConfig -ConfigObject $cfg -PropertyName "IncludeSecurity" -Setter {
            param($v)
            if ($null -ne $v) {
                if ([bool]$v) { $script:IncludeSecurity = $true } else { $script:IncludeSecurity = $false }
            }
        }
    }
}

$resolvedModulePath = Resolve-AbsolutePath -PathValue $ModulePath
$resolvedOutputRoot = Resolve-AbsolutePath -PathValue $OutputRoot

Write-Host "== AD Discovery Runner ==" -ForegroundColor Cyan
Write-Host ("Environment:     {0}" -f $Environment)
Write-Host ("OutputRoot:      {0}" -f $resolvedOutputRoot)
Write-Host ("CustomerName:    {0}" -f $CustomerName)
Write-Host ("Server:          {0}" -f $(if ([string]::IsNullOrWhiteSpace($Server)) { "<auto>" } else { $Server }))
Write-Host ("IncludeSecurity: {0}" -f $IncludeSecurity.IsPresent)
Write-Host ("PreflightOnly:   {0}" -f $PreflightOnly.IsPresent)
Write-Host ("ModulePath:      {0}" -f $resolvedModulePath)
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    Write-Host ("ConfigPath:      {0}" -f (Resolve-AbsolutePath -PathValue $ConfigPath))
}
Write-Host ""

$failures = @()
$warnings = @()

if (-not (Test-Path -LiteralPath $resolvedModulePath -PathType Leaf)) {
    $failures += "Module manifest not found: $resolvedModulePath"
}

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    $warnings += "Recommended runtime is Windows PowerShell 5.1. Current: $($PSVersionTable.PSVersion)"
}

if ($env:OS -ne "Windows_NT") {
    $failures += "Windows OS is required for AD discovery."
}

try {
    Test-IsWritablePath -PathValue $resolvedOutputRoot
} catch {
    $failures += "OutputRoot not writable: $resolvedOutputRoot. $($_.Exception.Message)"
}

if ($failures.Count -eq 0) {
    try {
        Import-Module -Name $resolvedModulePath -Force -ErrorAction Stop
    } catch {
        $failures += "Failed to import module: $resolvedModulePath. $($_.Exception.Message)"
    }
}

if ($failures.Count -eq 0) {
    foreach ($requiredFn in @("Invoke-AdDiscoveryExport", "Invoke-AdDiscovery")) {
        if (-not (Get-Command $requiredFn -ErrorAction SilentlyContinue)) {
            $failures += "Required function missing after import: $requiredFn"
        }
    }

    if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) {
        $failures += "ActiveDirectory module/cmdlets not available (Get-ADDomain missing)."
    }

    if ($IncludeSecurity -and -not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {
        $warnings += "GroupPolicy cmdlets not found (Get-GPO). Some security/GPO datasets may be partial."
    }
}

if ($warnings.Count -gt 0) {
    Write-Host "Warnings:" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host ("  - {0}" -f $w) -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($failures.Count -gt 0) {
    Write-Host "Preflight failed:" -ForegroundColor Red
    foreach ($f in $failures) {
        Write-Host ("  - {0}" -f $f) -ForegroundColor Red
    }
    exit 1
}

Write-Host "Preflight checks passed." -ForegroundColor Green
if ($PreflightOnly) {
    Write-Host "Preflight-only mode complete."
    exit 0
}

if (-not (Test-Path -LiteralPath $resolvedOutputRoot)) {
    New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
}

$logFile = Join-Path $resolvedOutputRoot ("ad-discovery-runner-{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$transcriptStarted = $false

try {
    Start-Transcript -Path $logFile -Force | Out-Null
    $transcriptStarted = $true

    $invokeParams = @{
        Environment = $Environment
        OutputRoot  = $resolvedOutputRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($CustomerName)) {
        $invokeParams.CustomerName = $CustomerName
    }
    if (-not [string]::IsNullOrWhiteSpace($Server)) {
        $invokeParams.Server = $Server
    }
    if ($IncludeSecurity) {
        $invokeParams.IncludeSecurity = $true
    }

    $result = Invoke-AdDiscoveryExport @invokeParams
    if (-not $result -or -not ($result.PSObject.Properties.Name -contains "RunRoot")) {
        throw "Invoke-AdDiscoveryExport did not return a result object with RunRoot."
    }

    Write-Host ""
    Write-Host "[OK] AD discovery run completed." -ForegroundColor Green
    Write-Host ("RunRoot: {0}" -f $result.RunRoot) -ForegroundColor Cyan
    Write-Host ("Log:     {0}" -f $logFile) -ForegroundColor Cyan

    $result
    exit 0
} catch {
    Write-Host ("[FAIL] AD discovery run failed: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Log: {0}" -f $logFile) -ForegroundColor Yellow
    exit 1
} finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}
