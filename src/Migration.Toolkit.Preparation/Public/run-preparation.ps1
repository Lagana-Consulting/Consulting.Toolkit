<#
.SYNOPSIS
Run ADMT prerequisite testing or preparation for the current source or target environment.

.EXAMPLE
& ".\run-preparation.ps1" -Role Source -OutputRoot "C:\Temp\AdmtPrep"

.EXAMPLE
& ".\run-preparation.ps1" -Role Source -Apply -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Source', 'Target')]
    [string]$Role,

    [string]$ConfigPath,

    [string]$OutputRoot,

    [securestring]$ServiceAccountPassword,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $moduleRoot 'Migration.Toolkit.Preparation.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
    throw "Module manifest not found: $moduleManifest"
}

Import-Module $moduleManifest -Force

$params = @{
    Role = $Role
}
if ($PSBoundParameters.ContainsKey('ConfigPath') -and -not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    $params.ConfigPath = $ConfigPath
}
if ($PSBoundParameters.ContainsKey('OutputRoot') -and -not [string]::IsNullOrWhiteSpace($OutputRoot)) {
    $params.OutputRoot = $OutputRoot
}

if ($Apply) {
    if ($PSBoundParameters.ContainsKey('ServiceAccountPassword')) {
        $params.ServiceAccountPassword = $ServiceAccountPassword
    }
    $result = Invoke-AdmtPreparation @params -WhatIf:$WhatIfPreference
}
else {
    $result = Test-AdmtPrerequisite @params
}

Write-Host ""
Write-Host "ADMT preparation check complete." -ForegroundColor Green
Write-Host "  Computer: $($result.ComputerName)" -ForegroundColor Yellow
Write-Host "  Role: $($result.Role)" -ForegroundColor Yellow
Write-Host "  Passed: $($result.PassCount)" -ForegroundColor Yellow
Write-Host "  Warnings/Manual: $($result.WarningCount)" -ForegroundColor Yellow
Write-Host "  Failed: $($result.FailureCount)" -ForegroundColor Yellow
if ($result.CsvPath) {
    Write-Host "  CSV: $($result.CsvPath)" -ForegroundColor Yellow
}
if ($result.JsonPath) {
    Write-Host "  JSON: $($result.JsonPath)" -ForegroundColor Yellow
}

$result
