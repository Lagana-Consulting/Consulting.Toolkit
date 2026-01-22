function Invoke-LcDiscoveryComparison {
  <#
  .SYNOPSIS
  Orchestrate discovery runs in source and target environments and generate comparison reports.

  .DESCRIPTION
  Runs AD discovery in both source and target environments, organizes outputs, and generates:
  - Side-by-side metrics comparison HTML
  - Migration readiness validation checklist
  - Consolidated summary with key findings

  Outputs are organized as:
    OutputRoot/
      ADOnly_<source_timestamp>/         # Source discovery run
      ADOnly__target_<target_timestamp>/ # Target discovery run
      LC__Comparison__Report__*.html
      LC__Migration__Readiness__Checklist__*.html

  .PARAMETER SourceServer
  Domain controller or GC in source forest to query (optional)

  .PARAMETER TargetServer
  Domain controller or GC in target forest to query (optional)

  .PARAMETER OutputRoot
  Root folder for all discovery outputs. Default: c:\scripts\Reports

  .PARAMETER CustomerName
  Customer name for report headers (optional)

  .PARAMETER GenerateReports
  If $true, also generates assessment, planning, LOE, and comparison reports (default: $true)

  .EXAMPLE
  Invoke-LcDiscoveryComparison -CustomerName "Contoso Corp"

  .EXAMPLE
  Invoke-LcDiscoveryComparison -SourceServer "dc1.source.com" -TargetServer "dc1.target.com" -OutputRoot "E:\Reports"
  #>

  [CmdletBinding()]
  param(
    [string]$SourceServer,
    [string]$TargetServer,
    [string]$OutputRoot = "c:\scripts\Reports",
    [string]$CustomerName = "Organization",
    [switch]$GenerateReports,
    [switch]$OpenReports
  )

  $discoveryScript = "c:\scripts\AD_Discovery_ADOnly_LC.ps1"

  if (-not (Test-Path -LiteralPath $discoveryScript)) {
    throw "Discovery script not found: $discoveryScript. Update path or copy script to c:\scripts\."
  }

  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "AD Discovery Comparison Orchestrator" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""

  # ========================================
  # Run source discovery
  # ========================================
  Write-Host "[1/5] Starting SOURCE environment discovery..." -ForegroundColor Yellow
  $sourceArgs = @{
    Environment  = "Source"
    OutputRoot   = $OutputRoot
    Prefix       = "ADOnly"
    CustomerName = $CustomerName
  }
  if ($SourceServer) { $sourceArgs['Server'] = $SourceServer }

  $sourceRunResult = & $discoveryScript @sourceArgs
  $sourceRunRoot = Get-ChildItem -Path $OutputRoot -Directory |
  Where-Object { $_.Name -match '^ADOnly_' } |
  Sort-Object -Property CreationTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName

  if (-not $sourceRunRoot) {
    throw "Source discovery failed: no output folder created"
  }
  Write-Host "  [OK] Source discovery complete: $sourceRunRoot" -ForegroundColor Green
  Write-Host ""

  # ========================================
  # Run target discovery
  # ========================================
  Write-Host "[2/5] Starting TARGET environment discovery..." -ForegroundColor Yellow
  $targetArgs = @{
    Environment  = "Target"
    OutputRoot   = $OutputRoot
    Prefix       = "ADOnly"
    CustomerName = $CustomerName
  }
  if ($TargetServer) { $targetArgs['Server'] = $TargetServer }

  $targetRunResult = & $discoveryScript @targetArgs
  $targetRunRoot = Get-ChildItem -Path $OutputRoot -Directory |
  Where-Object { $_.Name -match '^ADOnly__target_' } |
  Sort-Object -Property CreationTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName

  if (-not $targetRunRoot) {
    throw "Target discovery failed: no output folder created"
  }
  Write-Host "  [OK] Target discovery complete: $targetRunRoot" -ForegroundColor Green
  Write-Host ""

  # ========================================
  # Generate comparison reports
  # ========================================
  Write-Host "[3/5] Generating environment comparison report..." -ForegroundColor Yellow
  $comparisonReport = New-LcEnvironmentComparisonReport -SourceRunRoot $sourceRunRoot -TargetRunRoot $targetRunRoot -CustomerName $CustomerName
  Write-Host "  [OK] Comparison report: $($comparisonReport.ReportPath)" -ForegroundColor Green
  Write-Host ""

  # ========================================
  # Generate readiness checklist
  # ========================================
  Write-Host "[4/5] Generating migration readiness checklist..." -ForegroundColor Yellow
  $readinessChecklist = New-LcMigrationReadinessChecklist -SourceRunRoot $sourceRunRoot -TargetRunRoot $targetRunRoot -CustomerName $CustomerName
  Write-Host "  [OK] Readiness checklist: $($readinessChecklist.ChecklistPath)" -ForegroundColor Green
  Write-Host "    - $($readinessChecklist.PassItems) items passed automatically" -ForegroundColor Green
  Write-Host "    - $($readinessChecklist.FailItems) items require attention" -ForegroundColor Red
  Write-Host "    - $($readinessChecklist.ManualItems) items require manual verification" -ForegroundColor Yellow
  Write-Host ""

  # ========================================
  # Generate detailed reports (optional)
  # ========================================
  Write-Host "[5/5] Generating detailed assessment and planning reports..." -ForegroundColor Yellow

  $assessmentSource = New-LcAssessmentReport -RunRoot $sourceRunRoot -OutputPath (Join-Path $sourceRunRoot 'LC__Assessment__Report__Source.html') -CustomerName $CustomerName
  Write-Host "  [OK] Source assessment report: $($assessmentSource.ReportPath)" -ForegroundColor Green

  $assessmentTarget = New-LcAssessmentReport -RunRoot $targetRunRoot -OutputPath (Join-Path $targetRunRoot 'LC__Assessment__Report__Target.html') -CustomerName $CustomerName
  Write-Host "  [OK] Target assessment report: $($assessmentTarget.ReportPath)" -ForegroundColor Green

  $planningReport = New-LcMigrationPlanningReport -RunRoot $sourceRunRoot -OutputPath (Join-Path $sourceRunRoot 'LC__Migration__Planning__Report.html') -CustomerName $CustomerName
  Write-Host "  [OK] Migration planning report: $($planningReport.ReportPath)" -ForegroundColor Green

  $loeExcel = New-LcMigrationLoeExcel -RunRoot $sourceRunRoot -OutputPath (Join-Path $sourceRunRoot "LC__Migration__LOE__$($CustomerName)__Source.xlsx") -CustomerName $CustomerName
  Write-Host "  [OK] LOE estimation workbook: $($loeExcel)" -ForegroundColor Green

  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "[COMPLETE] Discovery Comparison Complete" -ForegroundColor Green
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""

  # Print summary
  Write-Host "SUMMARY:" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Source Discovery Output:" -ForegroundColor Yellow
  Write-Host "  Path: $sourceRunRoot" -ForegroundColor White
  Write-Host ""

  Write-Host "Target Discovery Output:" -ForegroundColor Yellow
  Write-Host "  Path: $targetRunRoot" -ForegroundColor White
  Write-Host ""

  Write-Host "Comparison Reports:" -ForegroundColor Yellow
  Write-Host "  - Environment Comparison: $($comparisonReport.ReportPath)" -ForegroundColor White
  Write-Host "  - Readiness Checklist: $($readinessChecklist.ChecklistPath)" -ForegroundColor White
  Write-Host ""

  Write-Host "Assessment and Planning (Source):" -ForegroundColor Yellow
  Write-Host "  - Assessment Report: $($assessmentSource.ReportPath)" -ForegroundColor White
  Write-Host "  - Planning Report: $($planningReport.ReportPath)" -ForegroundColor White
  Write-Host "  - LOE Estimation: $($loeExcel)" -ForegroundColor White
  Write-Host ""

  # Open reports if requested
  if ($OpenReports) {
    Write-Host "Opening reports..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $comparisonReport.ReportPath) {
      Invoke-Item -LiteralPath $comparisonReport.ReportPath
    }
    if (Test-Path -LiteralPath $readinessChecklist.ChecklistPath) {
      Start-Sleep -Seconds 2
      Invoke-Item -LiteralPath $readinessChecklist.ChecklistPath
    }
  }

  return [pscustomobject]@{
    SourceRunRoot      = $sourceRunRoot
    TargetRunRoot      = $targetRunRoot
    ComparisonReport   = $comparisonReport.ReportPath
    ReadinessChecklist = $readinessChecklist.ChecklistPath
    SourceAssessment   = $assessmentSource.ReportPath
    TargetAssessment   = $assessmentTarget.ReportPath
    PlanningReport     = $planningReport.ReportPath
    LoeExcel           = $loeExcel
  }
}
