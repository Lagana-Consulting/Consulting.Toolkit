<#
.SYNOPSIS
Runs environment and module smoke checks for Consulting.Toolkit.Discovery.

.DESCRIPTION
Performs quick validation for customer/operator hosts before full AD discovery runs.

.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ADDiscoverySmoke.ps1
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputRoot = (Join-Path $env:TEMP "ADDiscoverySmoke"),

    [Parameter()]
    [string]$ModulePath,

    [Parameter()]
    [switch]$IncludeSecurity
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

function Add-CheckResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Message
    )

    $script:results += [pscustomobject]@{
        Check   = $Name
        Status  = $Status
        Message = $Message
    }
}

function Test-WritablePath {
    param([Parameter(Mandatory)][string]$PathValue)

    if (-not (Test-Path -LiteralPath $PathValue)) {
        New-Item -ItemType Directory -Path $PathValue -Force | Out-Null
    }

    $probe = Join-Path $PathValue (".ad-smoke-{0}.tmp" -f [guid]::NewGuid().ToString("N"))
    Set-Content -Path $probe -Value "ok" -Encoding UTF8
    Remove-Item -LiteralPath $probe -Force
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ModulePath)) {
    $ModulePath = Join-Path $moduleRoot "Consulting.Toolkit.Discovery.psd1"
}

$resolvedModulePath = Resolve-AbsolutePath -PathValue $ModulePath
$resolvedOutputRoot = Resolve-AbsolutePath -PathValue $OutputRoot

$script:results = @()

if ($env:OS -eq "Windows_NT") {
    Add-CheckResult -Name "Windows OS" -Status "PASS" -Message "Windows OS detected."
} else {
    Add-CheckResult -Name "Windows OS" -Status "FAIL" -Message "Windows OS is required for AD discovery."
}

if ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) {
    Add-CheckResult -Name "PowerShell Version" -Status "PASS" -Message "Running on Windows PowerShell 5.1."
} else {
    Add-CheckResult -Name "PowerShell Version" -Status "WARN" -Message ("Recommended: Windows PowerShell 5.1. Current: {0}" -f $PSVersionTable.PSVersion)
}

if (Test-Path -LiteralPath $resolvedModulePath -PathType Leaf) {
    Add-CheckResult -Name "Module Manifest Path" -Status "PASS" -Message ("Found: {0}" -f $resolvedModulePath)
} else {
    Add-CheckResult -Name "Module Manifest Path" -Status "FAIL" -Message ("Not found: {0}" -f $resolvedModulePath)
}

try {
    Test-WritablePath -PathValue $resolvedOutputRoot
    Add-CheckResult -Name "Output Root Writable" -Status "PASS" -Message ("Writable: {0}" -f $resolvedOutputRoot)
} catch {
    Add-CheckResult -Name "Output Root Writable" -Status "FAIL" -Message ("Not writable: {0}. {1}" -f $resolvedOutputRoot, $_.Exception.Message)
}

if ((@($script:results | Where-Object { $_.Status -eq "FAIL" }).Count) -eq 0) {
    try {
        Import-Module -Name $resolvedModulePath -Force -ErrorAction Stop
        Add-CheckResult -Name "Module Import" -Status "PASS" -Message "Module import succeeded."
    } catch {
        Add-CheckResult -Name "Module Import" -Status "FAIL" -Message ("Module import failed: {0}" -f $_.Exception.Message)
    }
}

if ((@($script:results | Where-Object { $_.Status -eq "FAIL" }).Count) -eq 0) {
    foreach ($fn in @("Invoke-AdDiscoveryExport", "Invoke-AdDiscovery")) {
        if (Get-Command $fn -ErrorAction SilentlyContinue) {
            Add-CheckResult -Name ("Command: {0}" -f $fn) -Status "PASS" -Message "Available."
        } else {
            Add-CheckResult -Name ("Command: {0}" -f $fn) -Status "FAIL" -Message "Not found."
        }
    }

    if (Get-Command Get-ADDomain -ErrorAction SilentlyContinue) {
        Add-CheckResult -Name "ActiveDirectory Cmdlets" -Status "PASS" -Message "Get-ADDomain available."
    } else {
        Add-CheckResult -Name "ActiveDirectory Cmdlets" -Status "FAIL" -Message "Get-ADDomain missing. Install RSAT Active Directory module."
    }

    if ($IncludeSecurity) {
        if (Get-Command Get-GPO -ErrorAction SilentlyContinue) {
            Add-CheckResult -Name "GroupPolicy Cmdlets" -Status "PASS" -Message "Get-GPO available."
        } else {
            Add-CheckResult -Name "GroupPolicy Cmdlets" -Status "WARN" -Message "Get-GPO missing. Some security/GPO datasets may be partial."
        }
    }
}

Write-Host "== AD Discovery Smoke Check Results ==" -ForegroundColor Cyan
$script:results | Format-Table -AutoSize

$failCount = @($script:results | Where-Object { $_.Status -eq "FAIL" }).Count
$warnCount = @($script:results | Where-Object { $_.Status -eq "WARN" }).Count
$passCount = @($script:results | Where-Object { $_.Status -eq "PASS" }).Count

Write-Host ""
Write-Host ("Summary: PASS={0} WARN={1} FAIL={2}" -f $passCount, $warnCount, $failCount)

if ($failCount -gt 0) {
    exit 1
}

exit 0
