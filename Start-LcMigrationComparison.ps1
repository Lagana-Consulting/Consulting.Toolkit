#!/usr/bin/env pwsh
<#
.SYNOPSIS
Quick-start script for AD migration discovery and comparison workflow.

.DESCRIPTION
Run this script interactively to:
1. Enter customer and environment details
2. Automatically run discovery in source and target
3. Generate all comparison and readiness reports
4. Open reports in viewer

.EXAMPLE
.\Start-LcMigrationComparison.ps1
#>

param(
    [switch]$UseDefaults
)

# Import module
$toolkitPath = "$PSScriptRoot\src\Lagana.Consulting.Toolkit"
if (-not (Test-Path $toolkitPath)) {
    Write-Error "Toolkit not found at $toolkitPath"
    exit 1
}

Import-Module $toolkitPath -Force

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Lagana Consulting AD Migration Discovery & Comparison    ║" -ForegroundColor Cyan
Write-Host "║  Full-Path Implementation                                 ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Get inputs
if ($UseDefaults) {
    $customerName = "Test Organization"
    $outputRoot = "C:\scripts\Reports"
    $sourceServer = ""
    $targetServer = ""
} else {
    Write-Host "Please provide migration details:" -ForegroundColor Yellow
    Write-Host ""

    $customerName = Read-Host "  Customer Name (default: Test Organization)"
    if ([string]::IsNullOrWhiteSpace($customerName)) { $customerName = "Test Organization" }

    $outputRoot = Read-Host "  Output Root Path (default: C:\scripts\Reports)"
    if ([string]::IsNullOrWhiteSpace($outputRoot)) { $outputRoot = "C:\scripts\Reports" }

    $sourceServer = Read-Host "  Source Server (DC/GC, optional)"
    $targetServer = Read-Host "  Target Server (DC/GC, optional)"
}

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Customer: $customerName" -ForegroundColor White
Write-Host "  Output: $outputRoot" -ForegroundColor White
Write-Host "  Source Server: $(if ($sourceServer) { $sourceServer } else { '(Auto-detect)' })" -ForegroundColor White
Write-Host "  Target Server: $(if ($targetServer) { $targetServer } else { '(Auto-detect)' })" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "  Proceed? (Y/n)"
if ($confirm -ne "" -and $confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Starting discovery and comparison workflow..." -ForegroundColor Green
Write-Host ""

try {
    $params = @{
        OutputRoot      = $outputRoot
        CustomerName    = $customerName
        GenerateReports = $true
        OpenReports     = $true
    }

    if ($sourceServer) { $params['SourceServer'] = $sourceServer }
    if ($targetServer) { $params['TargetServer'] = $targetServer }

    $result = Invoke-LcDiscoveryComparison @params

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "✓ Discovery and Comparison Complete!" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "Generated Reports:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Comparison & Readiness:" -ForegroundColor Yellow
    Write-Host "    • $($result.ComparisonReport)" -ForegroundColor White
    Write-Host "    • $($result.ReadinessChecklist)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Assessment (Source):" -ForegroundColor Yellow
    Write-Host "    • $($result.SourceAssessment)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Assessment (Target):" -ForegroundColor Yellow
    Write-Host "    • $($result.TargetAssessment)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Planning & LOE:" -ForegroundColor Yellow
    Write-Host "    • $($result.PlanningReport)" -ForegroundColor White
    Write-Host "    • $($result.LoeExcel)" -ForegroundColor White
    Write-Host ""

    Write-Host "Next Steps:" -ForegroundColor Cyan
    Write-Host "  1. Review Comparison Report for object count deltas" -ForegroundColor White
    Write-Host "  2. Complete Readiness Checklist items" -ForegroundColor White
    Write-Host "  3. Address any identified failures" -ForegroundColor White
    Write-Host "  4. Use LOE workbook to plan migration waves" -ForegroundColor White
    Write-Host "  5. Dry-run migration procedures in lab" -ForegroundColor White
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "✗ Error during discovery:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  • Verify source and target servers are reachable" -ForegroundColor White
    Write-Host "  • Ensure you have AD read permissions" -ForegroundColor White
    Write-Host "  • Check discovery script location: c:\scripts\AD_Discovery_ADOnly_LC.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}
