# Comprehensive test of the assessment automation
param(
    [string]$DiscoveryPath = ".\compare\ADOnly_20260121-132028"
)

Write-Host "=== Full Assessment Automation Test ===" -ForegroundColor Cyan
Write-Host "Discovery Path: $DiscoveryPath" -ForegroundColor Yellow
Write-Host ""

# Ensure output directory
$outputPath = ".\output\automation-test"
if (-not (Test-Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
}

# Import module
Import-Module ".\src\Migration.Toolkit" -Force
Import-Module ".\src\Migration.Toolkit.Assessment" -Force

Write-Host "Running Invoke-ADAssessmentAutomation..." -ForegroundColor Yellow

try {
    $result = Invoke-ADAssessmentAutomation `
        -DiscoveryOutputPath $DiscoveryPath `
        -OutputPath $outputPath `
        -Verbose 4>&1

    Write-Host "`n=== Results ===" -ForegroundColor Green

    # Count successes and failures from output
    $successCount = ($result -match "SUCCESS" | Measure-Object).Count
    $failureCount = ($result -match "ERROR|WARNING" | Measure-Object).Count

    # Show last 50 lines of output which should have the summary
    Write-Host "=== Last Output Lines ===" -ForegroundColor Cyan
    $result | Select-Object -Last 60 | ForEach-Object { Write-Host $_ }

}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host $_.Exception.StackTrace -ForegroundColor Red
}

# Check if document was created
Write-Host "`n=== Generated Documents ===" -ForegroundColor Cyan
Get-ChildItem $outputPath -Filter "*.docx" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  ✓ $($_.Name) ($('{0:N2}' -f ($_.Length/1MB)) MB)" -ForegroundColor Green
}
