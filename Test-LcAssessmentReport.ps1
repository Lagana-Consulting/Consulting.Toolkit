# Test script for New-LcAssessmentReport
# Run this in your lab environment where discovery outputs exist

param(
    [string]$DiscoveryPath
)

# If no path provided, find the most recent ADOnly output
if (-not $DiscoveryPath) {
    $DiscoveryPath = Get-ChildItem "c:\scripts\Reports" -Directory -Filter "ADOnly*" -ErrorAction SilentlyContinue |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}

if (-not $DiscoveryPath) {
    Write-Error "No discovery output folder found. Specify -DiscoveryPath or ensure c:\scripts\Reports\ADOnly* folder exists."
    exit 1
}

Write-Host "=== New-LcAssessmentReport Test ===" -ForegroundColor Cyan
Write-Host "Discovery Path: $DiscoveryPath"
Write-Host ""

# Load module from source
$ModulePath = "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\lc-toolkit\src\Lagana.Consulting.Toolkit"
Write-Host "Loading module from: $ModulePath" -ForegroundColor Yellow

if (-not (Test-Path $ModulePath)) {
    Write-Error "Module path does not exist: $ModulePath"
    exit 1
}

Import-Module "$ModulePath\Lagana.Consulting.Toolkit.psd1" -Force

# Test the function
Write-Host "Generating HTML report..." -ForegroundColor Yellow
try {
    $result = New-LcAssessmentReport -DiscoveryOutputPath $DiscoveryPath

    Write-Host "`n=== Report Generated Successfully ===" -ForegroundColor Green
    Write-Host "Report Path:     $($result.ReportPath)"
    Write-Host "Forest:          $($result.ForestName)"
    Write-Host "Health Score:    $($result.HealthScore)/100 ($($result.HealthStatus))"
    Write-Host "Total Findings:  $($result.TotalFindings)"
    Write-Host "Critical Risks:  $($result.CriticalRisks)"
    Write-Host "High Risks:      $($result.HighRisks)"
    Write-Host ""
    Write-Host "Opening report in browser..." -ForegroundColor Yellow
    Invoke-Item $result.ReportPath
} catch {
    Write-Error "Error generating report: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}
