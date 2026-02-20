<#
.SYNOPSIS
Deterministically refreshes Status values in Indicator_Discovery_Matrix.csv.

.DESCRIPTION
Sets each row Status to:
  - Have: all required datasets are currently considered available
  - Missing: one or more required datasets are not available

Availability baseline is built from:
  1) Dataset tokens that already appear on rows with Status=Have
  2) An explicit seed list for cloud/hybrid datasets collected by M365.Discovery.Collector

.PARAMETER MatrixPath
Path to Indicator_Discovery_Matrix.csv.

.PARAMETER WhatIf
Preview only; do not write file.

.EXAMPLE
.\tools\Refresh-IndicatorMatrixStatus.ps1

.EXAMPLE
.\tools\Refresh-IndicatorMatrixStatus.ps1 -WhatIf
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$MatrixPath = "src/Consulting.Toolkit.Discovery/Indicator_Discovery_Matrix.csv",

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MatrixPath)) {
    throw "Matrix file not found: $MatrixPath"
}

$rows = @(Import-Csv -LiteralPath $MatrixPath)
if ($rows.Count -eq 0) {
    throw "No rows loaded from matrix: $MatrixPath"
}

$available = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

# 1) Seed from existing Have rows
foreach ($row in $rows) {
    if ($row.Status -ne 'Have') { continue }
    if ([string]::IsNullOrWhiteSpace($row.'Required Discovery Datasets')) { continue }

    foreach ($ds in ($row.'Required Discovery Datasets' -split ';')) {
        $token = $ds.Trim()
        if ($token) { [void]$available.Add($token) }
    }
}

# 2) Explicit cloud/hybrid datasets currently collected
$explicitAvailable = @(
    'Entra_Users',
    'Entra_Groups',
    'Entra_Applications',
    'Entra_ServicePrincipals',
    'Entra_RoleAssignments',
    'Entra_ConditionalAccessPolicies',
    'Entra_CrossTenantAccess',
    'Entra_GuestUsers',
    'Entra_SignInActivity',
    'Entra_AuthMethodsCoverage',
    'Entra_GroupInventory',
    'Entra_AppCredentials',
    'Entra_AppAssignments',
    'Entra_DirectorySettings',
    'Hybrid_AADConnectConfig',
    'M365_Groups',
    'M365_OneDrive_Usage',
    'M365_SharePoint_Usage',
    'M365_Teams_Usage',
    'M365_Exchange_Usage'
)
foreach ($ds in $explicitAvailable) { [void]$available.Add($ds) }

$changes = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $oldStatus = $row.Status
    $required = @()

    if (-not [string]::IsNullOrWhiteSpace($row.'Required Discovery Datasets')) {
        $required = @(
            $row.'Required Discovery Datasets' -split ';' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
        )
    }

    if ($required.Count -gt 0) {
        $allPresent = $true
        foreach ($ds in $required) {
            if (-not $available.Contains($ds)) {
                $allPresent = $false
                break
            }
        }
        $row.Status = if ($allPresent) { 'Have' } else { 'Missing' }
    }

    if ($row.Status -ne $oldStatus) {
        $changes.Add([pscustomobject]@{
            Phase         = $row.Phase
            Category      = $row.Category
            IndicatorName = $row.'Indicator Name'
            OldStatus     = $oldStatus
            NewStatus     = $row.Status
        }) | Out-Null
    }
}

if (-not $WhatIf) {
    $rows | Export-Csv -LiteralPath $MatrixPath -NoTypeInformation -Encoding UTF8
}

Write-Host "Matrix: $MatrixPath"
Write-Host "Mode:   $([string]::new($(if ($WhatIf) { 'WhatIf (no write)' } else { 'Write' })))"
Write-Host "Changed rows: $($changes.Count)"

$statusSummary = $rows | Group-Object Status | Select-Object Name, Count
Write-Host "`nStatus summary:"
$statusSummary | Format-Table -AutoSize | Out-String | Write-Host

$phase3Summary = $rows | Where-Object { $_.Phase -eq 'Phase3' } | Group-Object Status | Select-Object Name, Count
Write-Host "Phase3 summary:"
$phase3Summary | Format-Table -AutoSize | Out-String | Write-Host

if ($changes.Count -gt 0) {
    Write-Host "Sample changes (up to 20):"
    $changes | Select-Object -First 20 | Format-Table -AutoSize | Out-String | Write-Host
}
