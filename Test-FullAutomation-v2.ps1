
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
    # Get template path
    $templatePath = (Get-ChildItem -Path ".\src\Migration.Toolkit.Assessment\config" -Filter "*.docx" -File | Select-Object -First 1).FullName

    if (-not $templatePath) {
        throw "No template found in config folder"
    }

    Write-Host "Using template: $templatePath" -ForegroundColor Yellow

    $result = & (Get-Command Invoke-ADAssessmentAutomation) `
        -OutputPath $outputPath `
        -Verbose 4>&1

    Write-Host "`n=== Results ===" -ForegroundColor Green
    Write-Host "Output lines: $(($result | Measure-Object).Count)"
    Write-Host ""

    # Show last 60 lines of output which should have the summary
    Write-Host "=== Last Output Lines ===" -ForegroundColor Cyan
    $result | Select-Object -Last 60 | ForEach-Object { Write-Host $_ }

}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}

# Check if document was created
Write-Host "`n=== Generated Documents ===" -ForegroundColor Cyan
Get-ChildItem $outputPath -Filter "*.docx" -ErrorAction SilentlyContinue | ForEach-Object {
    $sizeMB = '{0:N2}' -f ($_.Length / 1MB)
    Write-Host "Document: $($_.Name) ($sizeMB MB)" -ForegroundColor Green
}
