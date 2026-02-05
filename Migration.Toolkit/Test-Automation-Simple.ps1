
# Run full automation test
$discoveryPath = ".\compare\ADOnly_20260121-132028"
$outputPath = ".\output\automation-test"
$templatePath = Get-ChildItem -Path ".\src\Migration.Toolkit.Assessment\config" -Filter "*.docx" -File | Select-Object -First 1 -ExpandProperty FullName

if (-not (Test-Path $discoveryPath)) {
    Write-Error "Discovery path not found: $discoveryPath"
    exit 1
}

if (-not $templatePath) {
    Write-Error "Template not found"
    exit 1
}

Write-Host "=== Full Assessment Automation Test ===" -ForegroundColor Cyan
Write-Host "Discovery: $discoveryPath" -ForegroundColor Yellow
Write-Host "Template: $templatePath" -ForegroundColor Yellow
Write-Host "Output: $outputPath" -ForegroundColor Yellow

# Import modules
Import-Module ".\src\Migration.Toolkit" -Force
Import-Module ".\src\Migration.Toolkit.Assessment" -Force

# Run automation
Write-Host "`nRunning automation..." -ForegroundColor Cyan
try {
    $docPath = Invoke-ADAssessmentAutomation -DiscoveryOutputPath $discoveryPath -TemplatePath $templatePath -OutputPath $outputPath -Verbose 4>&1
    Write-Host "`nResult: $docPath" -ForegroundColor Green
}
catch {
    Write-Error "Automation failed: $_"
}

# Check generated documents
Write-Host "`n=== Generated Documents ===" -ForegroundColor Cyan
Get-ChildItem $outputPath -Filter "*.docx" -ErrorAction SilentlyContinue | ForEach-Object {
    $sizeMB = '{0:N2}' -f ($_.Length / 1MB)
    Write-Host "OK: $($_.Name) ($sizeMB MB)" -ForegroundColor Green
}
