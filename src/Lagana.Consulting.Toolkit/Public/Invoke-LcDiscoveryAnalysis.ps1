function Invoke-LcDiscoveryAnalysis {
  <#
  .SYNOPSIS
  Analyze pre-collected AD discovery data and generate assessment/migration reports.

  .DESCRIPTION
  Performs offline analysis of discovery data collected from source and target environments.
  Reads CSV files from discovery run folders and generates:
  - Source and target assessment reports (HTML)
  - Migration planning report
  - LOE estimation workbook
  - Environment comparison HTML
  - Migration readiness checklist
  - Cross-forest duplicate object analysis

  No Active Directory queries are performed—all analysis uses previously collected CSV data.

  .PARAMETER ConfigFile
  Path to JSON configuration file containing run roots and analysis settings.
  Example config:
  {
    "SourceRunRoot": "c:\\scripts\\Reports\\ADOnly_20260122-103045",
    "TargetRunRoot": "c:\\scripts\\Reports\\ADOnly__target_20260122-110230",
    "CustomerName": "Contoso Corp",
    "OutputRoot": "c:\\analysis\\Migration",
    "GenerateLoeForBoth": false,
    "IncludeTargetPlanning": false
  }

  .PARAMETER SourceRunRoot
  Path to source environment discovery output folder (alternative to ConfigFile)

  .PARAMETER TargetRunRoot
  Path to target environment discovery output folder (alternative to ConfigFile)

  .PARAMETER CustomerName
  Customer name for report headers

  .PARAMETER OutputRoot
  Root folder for analysis outputs. Default: SourceRunRoot

  .PARAMETER GenerateLoeForBoth
  Generate LOE workbooks for both source and target (default: source only)

  .PARAMETER IncludeTargetPlanning
  Generate migration planning report for target environment (default: source only)

  .EXAMPLE
  Invoke-LcDiscoveryAnalysis -ConfigFile "c:\analysis\config.json"

  .EXAMPLE
  Invoke-LcDiscoveryAnalysis -SourceRunRoot "c:\reports\ADOnly_..." -TargetRunRoot "c:\reports\ADOnly__target_..." -CustomerName "Contoso"
  #>

  [CmdletBinding(DefaultParameterSetName = 'Manual')]
  param(
    [Parameter(Mandatory, ParameterSetName = 'Config')]
    [string]$ConfigFile,

    [Parameter(Mandatory, ParameterSetName = 'Manual')]
    [string]$SourceRunRoot,

    [Parameter(Mandatory, ParameterSetName = 'Manual')]
    [string]$TargetRunRoot,

    [Parameter(ParameterSetName = 'Manual')]
    [string]$CustomerName = "Organization",

    [Parameter(ParameterSetName = 'Manual')]
    [string]$OutputRoot,

    [switch]$GenerateLoeForBoth,
    [switch]$IncludeTargetPlanning,
    [switch]$OpenReports
  )

  # Load config if provided
  if ($PSCmdlet.ParameterSetName -eq 'Config') {
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
      throw "Config file not found: $ConfigFile"
    }
    try {
      $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
      $SourceRunRoot = $config.SourceRunRoot
      $TargetRunRoot = $config.TargetRunRoot
      $CustomerName = if ($config.CustomerName) { $config.CustomerName } else { "Organization" }
      $OutputRoot = if ($config.OutputRoot) { $config.OutputRoot } else { $SourceRunRoot }
      if ($config.PSObject.Properties['GenerateLoeForBoth']) { $GenerateLoeForBoth = [bool]$config.GenerateLoeForBoth }
      if ($config.PSObject.Properties['IncludeTargetPlanning']) { $IncludeTargetPlanning = [bool]$config.IncludeTargetPlanning }
    } catch {
      throw "Failed to parse config file: $_"
    }
  }

  # Default output root to source run root if not specified
  if (-not $OutputRoot) {
    $OutputRoot = $SourceRunRoot
  }

  # Validate paths
  if (-not (Test-Path -LiteralPath $SourceRunRoot)) {
    throw "Source run root not found: $SourceRunRoot"
  }
  if (-not (Test-Path -LiteralPath $TargetRunRoot)) {
    throw "Target run root not found: $TargetRunRoot"
  }

  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "AD Discovery Analysis Engine" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Source: $SourceRunRoot" -ForegroundColor White
  Write-Host "Target: $TargetRunRoot" -ForegroundColor White
  Write-Host "Output: $OutputRoot" -ForegroundColor White
  Write-Host ""

  # Helper to safely import CSV
  function Import-CsvSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
      Write-Warning "CSV not found: $Path"
      return @()
    }
    try {
      return @(Import-Csv -Path $Path -ErrorAction Stop)
    } catch {
      Write-Warning "Failed to import $Path : $_"
      return @()
    }
  }

  # ========================================
  # Step 1: Generate source assessment report
  # ========================================
  Write-Host "[1/7] Generating source environment assessment..." -ForegroundColor Yellow
  $sourceAssessmentPath = Join-Path $OutputRoot "LC__Assessment__Report__Source.html"
  try {
    $assessmentSource = New-LcAssessmentReport -RunRoot $SourceRunRoot -OutputPath $sourceAssessmentPath -CustomerName $CustomerName
    Write-Host "  [OK] Source assessment: $sourceAssessmentPath" -ForegroundColor Green
  } catch {
    Write-Warning "Source assessment failed: $_"
    $assessmentSource = $null
  }
  Write-Host ""

  # ========================================
  # Step 2: Generate target assessment report
  # ========================================
  Write-Host "[2/7] Generating target environment assessment..." -ForegroundColor Yellow
  $targetAssessmentPath = Join-Path $OutputRoot "LC__Assessment__Report__Target.html"
  try {
    $assessmentTarget = New-LcAssessmentReport -RunRoot $TargetRunRoot -OutputPath $targetAssessmentPath -CustomerName $CustomerName
    Write-Host "  [OK] Target assessment: $targetAssessmentPath" -ForegroundColor Green
  } catch {
    Write-Warning "Target assessment failed: $_"
    $assessmentTarget = $null
  }
  Write-Host ""

  # ========================================
  # Step 3: Generate environment comparison
  # ========================================
  Write-Host "[3/7] Generating environment comparison report..." -ForegroundColor Yellow
  $comparisonPath = Join-Path $OutputRoot "LC__Environment__Comparison.html"
  try {
    $comparisonReport = New-LcEnvironmentComparisonReport -SourceRunRoot $SourceRunRoot -TargetRunRoot $TargetRunRoot -OutputPath $comparisonPath -CustomerName $CustomerName
    Write-Host "  [OK] Comparison report: $comparisonPath" -ForegroundColor Green
  } catch {
    Write-Warning "Comparison report failed: $_"
    $comparisonReport = $null
  }
  Write-Host ""

  # ========================================
  # Step 4: Generate readiness checklist
  # ========================================
  Write-Host "[4/7] Generating migration readiness checklist..." -ForegroundColor Yellow
  $checklistPath = Join-Path $OutputRoot "LC__Migration__Readiness__Checklist.html"
  try {
    $readinessChecklist = New-LcMigrationReadinessChecklist -SourceRunRoot $SourceRunRoot -TargetRunRoot $TargetRunRoot -OutputPath $checklistPath -CustomerName $CustomerName
    Write-Host "  [OK] Readiness checklist: $checklistPath" -ForegroundColor Green
    Write-Host "    - $($readinessChecklist.PassItems) items passed automatically" -ForegroundColor Green
    Write-Host "    - $($readinessChecklist.FailItems) items require attention" -ForegroundColor Red
    Write-Host "    - $($readinessChecklist.ManualItems) items require manual verification" -ForegroundColor Yellow
  } catch {
    Write-Warning "Readiness checklist failed: $_"
    $readinessChecklist = $null
  }
  Write-Host ""

  # ========================================
  # Step 5: Cross-forest duplicate object analysis
  # ========================================
  Write-Host "[5/7] Analyzing cross-forest duplicate objects..." -ForegroundColor Yellow
  $duplicatePath = Join-Path $OutputRoot "LC__Duplicate__Objects__Cross_Forest.csv"
  try {
    # Load source and target object CSVs
    $sourceDomainDir = Join-Path $SourceRunRoot '20_domains'
    $targetDomainDir = Join-Path $TargetRunRoot '20_domains'

    $sourceUsers = @()
    $sourceGroups = @()
    $sourceComputers = @()
    $targetUsers = @()
    $targetGroups = @()
    $targetComputers = @()

    # Load source objects
    Get-ChildItem -Path $sourceDomainDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $domainFolder = $_.FullName
      $sourceUsers += Import-CsvSafe (Join-Path $domainFolder 'LC__AD__Users__*.csv')
      $sourceGroups += Import-CsvSafe (Join-Path $domainFolder 'LC__AD__Groups__*.csv')
      $sourceComputers += Import-CsvSafe (Join-Path $domainFolder 'LC__AD__Computers__*.csv')
    }

    # Load target objects
    Get-ChildItem -Path $targetDomainDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $domainFolder = $_.FullName
      $targetUsers += Import-CsvSafe (Join-Path $domainFolder 'LC__AD__Users__*.csv')
      $targetGroups += Import-CsvSafe (Join-Path $domainFolder 'LC__AD__Groups__*.csv')
      $targetComputers += Import-CsvSafe (Join-Path $domainFolder 'LC__AD__Computers__*.csv')
    }

    # Tag with environment
    $sourceUsers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
    $sourceGroups | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
    $sourceComputers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
    $targetUsers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }
    $targetGroups | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }
    $targetComputers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }

    # Combine
    $allUsers = @($sourceUsers) + @($targetUsers)
    $allGroups = @($sourceGroups) + @($targetGroups)
    $allComputers = @($sourceComputers) + @($targetComputers)

    # Run duplicate check
    $duplicates = Get-LcDuplicateObjectsForAdmt -AllUsers $allUsers -AllGroups $allGroups -AllComputers $allComputers

    # Filter to cross-forest only (where ConflictingDomains contains both source and target)
    $crossForestDuplicates = @($duplicates | Where-Object {
        ($_.ConflictingDomains -match ';') -or
        ($_.ConflictCount -gt 1)
      })

    if ($crossForestDuplicates.Count -gt 0) {
      $crossForestDuplicates | Export-Csv -Path $duplicatePath -NoTypeInformation -Force
      Write-Host "  [OK] Cross-forest duplicates: $duplicatePath ($($crossForestDuplicates.Count) conflicts)" -ForegroundColor Yellow
    } else {
      Write-Host "  [OK] No cross-forest duplicate objects detected" -ForegroundColor Green
    }
  } catch {
    Write-Warning "Duplicate object analysis failed: $_"
    $crossForestDuplicates = @()
  }
  Write-Host ""

  # ========================================
  # Step 6: Generate migration planning report (source)
  # ========================================
  Write-Host "[6/7] Generating migration planning report..." -ForegroundColor Yellow
  $planningPath = Join-Path $OutputRoot "LC__Migration__Planning__Report__Source.html"
  try {
    $planningReport = New-LcMigrationPlanningReport -RunRoot $SourceRunRoot -OutputPath $planningPath -CustomerName $CustomerName
    Write-Host "  [OK] Planning report (source): $planningPath" -ForegroundColor Green
  } catch {
    Write-Warning "Planning report failed: $_"
    $planningReport = $null
  }

  if ($IncludeTargetPlanning) {
    $targetPlanningPath = Join-Path $OutputRoot "LC__Migration__Planning__Report__Target.html"
    try {
      $targetPlanningReport = New-LcMigrationPlanningReport -RunRoot $TargetRunRoot -OutputPath $targetPlanningPath -CustomerName $CustomerName
      Write-Host "  [OK] Planning report (target): $targetPlanningPath" -ForegroundColor Green
    } catch {
      Write-Warning "Target planning report failed: $_"
    }
  }
  Write-Host ""

  # ========================================
  # Step 7: Generate LOE workbook
  # ========================================
  Write-Host "[7/7] Generating LOE estimation workbook..." -ForegroundColor Yellow
  $loePathSource = Join-Path $OutputRoot "LC__Migration__LOE__Source.xlsx"
  try {
    $loeExcelSource = New-LcMigrationLoeExcel -RunRoot $SourceRunRoot -OutputPath $loePathSource -CustomerName $CustomerName
    Write-Host "  [OK] LOE workbook (source): $loePathSource" -ForegroundColor Green
  } catch {
    Write-Warning "LOE workbook failed: $_"
    $loeExcelSource = $null
  }

  if ($GenerateLoeForBoth) {
    $loePathTarget = Join-Path $OutputRoot "LC__Migration__LOE__Target.xlsx"
    try {
      $loeExcelTarget = New-LcMigrationLoeExcel -RunRoot $TargetRunRoot -OutputPath $loePathTarget -CustomerName $CustomerName
      Write-Host "  [OK] LOE workbook (target): $loePathTarget" -ForegroundColor Green
    } catch {
      Write-Warning "Target LOE workbook failed: $_"
    }
  }
  Write-Host ""

  # ========================================
  # Summary
  # ========================================
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "[COMPLETE] Analysis Complete" -ForegroundColor Green
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""

  Write-Host "OUTPUTS GENERATED:" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Assessment Reports:" -ForegroundColor Yellow
  Write-Host "  - Source: $sourceAssessmentPath" -ForegroundColor White
  Write-Host "  - Target: $targetAssessmentPath" -ForegroundColor White
  Write-Host ""
  Write-Host "Comparison & Readiness:" -ForegroundColor Yellow
  Write-Host "  - Environment Comparison: $comparisonPath" -ForegroundColor White
  Write-Host "  - Readiness Checklist: $checklistPath" -ForegroundColor White
  if ($crossForestDuplicates.Count -gt 0) {
    Write-Host "  - Cross-Forest Duplicates: $duplicatePath ($($crossForestDuplicates.Count) conflicts)" -ForegroundColor Yellow
  }
  Write-Host ""
  Write-Host "Planning & LOE:" -ForegroundColor Yellow
  Write-Host "  - Planning Report (Source): $planningPath" -ForegroundColor White
  Write-Host "  - LOE Workbook (Source): $loePathSource" -ForegroundColor White
  Write-Host ""

  # Open reports if requested
  if ($OpenReports) {
    Write-Host "Opening key reports..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $comparisonPath) {
      Invoke-Item -LiteralPath $comparisonPath
    }
    if (Test-Path -LiteralPath $checklistPath) {
      Start-Sleep -Seconds 2
      Invoke-Item -LiteralPath $checklistPath
    }
  }

  return [pscustomobject]@{
    OutputRoot              = $OutputRoot
    SourceAssessment        = $sourceAssessmentPath
    TargetAssessment        = $targetAssessmentPath
    ComparisonReport        = $comparisonPath
    ReadinessChecklist      = $checklistPath
    CrossForestDuplicates   = if ($crossForestDuplicates.Count -gt 0) { $duplicatePath } else { $null }
    PlanningReport          = $planningPath
    LoeWorkbook             = $loePathSource
    DuplicateConflictCount  = $crossForestDuplicates.Count
  }
}
