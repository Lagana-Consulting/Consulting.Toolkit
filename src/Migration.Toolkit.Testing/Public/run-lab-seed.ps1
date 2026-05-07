<#
.SYNOPSIS
Seed a lab AD domain from migration discovery output.

.EXAMPLE
& ".\run-lab-seed.ps1" `
  -RunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -StagingOuName "Migration Lab Staging" `
  -UserLimit 25 `
  -GroupLimit 25 `
  -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$RunRoot,

    [string]$StagingOuName = 'Migration Lab Staging',

    [string]$StagingBaseDn,

    [int]$UserLimit = 0,

    [int]$GroupLimit = 0,

    [switch]$PreserveSourceOuPath = $true,

    [switch]$IncludeBuiltInGroups,

    [switch]$IncludeBuiltInUsers,

    [switch]$CreateDisabledUsers,

    [string]$DefaultPassword = 'P@ssw0rd!12345',

    [string]$UserPrincipalNameSuffix,

    [switch]$PlanOnly,

    [switch]$StopOnError,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $moduleRoot 'Migration.Toolkit.Testing.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
    throw "Module manifest not found: $moduleManifest"
}

Import-Module $moduleManifest -Force

$params = @{
    RunRoot              = $RunRoot
    StagingOuName        = $StagingOuName
    UserLimit            = $UserLimit
    GroupLimit           = $GroupLimit
    PreserveSourceOuPath = [bool]$PreserveSourceOuPath
    IncludeBuiltInGroups = [bool]$IncludeBuiltInGroups
    IncludeBuiltInUsers  = [bool]$IncludeBuiltInUsers
    CreateDisabledUsers  = [bool]$CreateDisabledUsers
    DefaultPassword      = $DefaultPassword
    PlanOnly             = [bool]$PlanOnly
    StopOnError          = [bool]$StopOnError
}

if ($PSBoundParameters.ContainsKey('StagingBaseDn') -and -not [string]::IsNullOrWhiteSpace($StagingBaseDn)) {
    $params.StagingBaseDn = $StagingBaseDn
}
if ($PSBoundParameters.ContainsKey('UserPrincipalNameSuffix') -and -not [string]::IsNullOrWhiteSpace($UserPrincipalNameSuffix)) {
    $params.UserPrincipalNameSuffix = $UserPrincipalNameSuffix
}
if ($PSBoundParameters.ContainsKey('OutputPath') -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $params.OutputPath = $OutputPath
}

$result = New-AdMigrationLabSeed @params -WhatIf:$WhatIfPreference

Write-Host ""
Write-Host "Migration lab seed complete." -ForegroundColor Green
Write-Host "  Staging Root: $($result.StagingRootDn)" -ForegroundColor Yellow
Write-Host "  Groups Seen: $($result.GroupsSeen)" -ForegroundColor Yellow
Write-Host "  Users Seen: $($result.UsersSeen)" -ForegroundColor Yellow
Write-Host "  Groups Created: $($result.GroupsCreated)" -ForegroundColor Yellow
Write-Host "  Users Created: $($result.UsersCreated)" -ForegroundColor Yellow
Write-Host "  Planned: $($result.Planned)" -ForegroundColor Yellow
Write-Host "  Skipped: $($result.Skipped)" -ForegroundColor Yellow
Write-Host "  Failed: $($result.Failed)" -ForegroundColor Yellow
if ($result.OutputPath) {
    Write-Host "  Output: $($result.OutputPath)" -ForegroundColor Yellow
}

$result
