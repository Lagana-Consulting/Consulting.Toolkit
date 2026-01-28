function Invoke-AdDiscoveryComparison {
  <#
  .SYNOPSIS
  Orchestrate discovery runs in source and target environments (data collection only).

  .DESCRIPTION
  Runs AD discovery in both source and target environments and saves raw CSV data.
  Creates a JSON configuration file for subsequent analysis using Invoke-AdDiscoveryAnalysis.

  This function ONLY collects data—no reports are generated.
  After collection, run Invoke-AdDiscoveryAnalysis with the generated config file.

  Outputs are organized as:
    OutputRoot/
      ADOnly_<source_timestamp>/         # Source discovery run
      ADOnly__target_<target_timestamp>/ # Target discovery run
      AD__Discovery__Config__*.json      # Analysis configuration

  .PARAMETER SourceServer
  Domain controller or GC in source forest to query (optional)

  .PARAMETER TargetServer
  Domain controller or GC in target forest to query (optional)

  .PARAMETER OutputRoot
  Root folder for all discovery outputs. Default: c:\scripts\Reports

  .PARAMETER CustomerName
  Customer name for analysis configuration (optional)

  .PARAMETER SkipConfigFile
  Skip generation of analysis config JSON (useful for ad-hoc collection)

  .EXAMPLE
  Invoke-AdDiscoveryComparison -CustomerName "Contoso Corp"
  # Collects data and creates config.json for later analysis

  .EXAMPLE
  Invoke-AdDiscoveryComparison -SourceServer "dc1.source.com" -TargetServer "dc1.target.com" -OutputRoot "E:\Reports"
  # Collects data from specific DCs
  #>

  [CmdletBinding()]
  param(
    [string]$SourceServer,
    [string]$TargetServer,
    [string]$OutputRoot = "c:\scripts\Reports",
    [string]$CustomerName = "Organization",
    [string]$DiscoveryScriptPath,
    [switch]$SkipConfigFile
  )

  # Default to workspace location if not specified
  if (-not $DiscoveryScriptPath) {
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $DiscoveryScriptPath = Join-Path $workspaceRoot "AD_Discovery_ADOnly_LC.ps1"
  }

  if (-not (Test-Path -LiteralPath $DiscoveryScriptPath)) {
    throw "Discovery script not found: $DiscoveryScriptPath. Specify -DiscoveryScriptPath parameter or ensure AD_Discovery_ADOnly_LC.ps1 exists in workspace root."
  }

  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "AD Discovery Data Collection" -ForegroundColor Cyan
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""

  # ========================================
  # Run source discovery
  # ========================================
  Write-Host "[1/2] Starting SOURCE environment discovery..." -ForegroundColor Yellow
  $sourceArgs = @{
    Environment  = "Source"
    OutputRoot   = $OutputRoot
    Prefix       = "ADOnly"
    CustomerName = $CustomerName
  }
  if ($SourceServer) { $sourceArgs['Server'] = $SourceServer }

  $sourceRunResult = & $DiscoveryScriptPath @sourceArgs
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
  Write-Host "[2/2] Starting TARGET environment discovery..." -ForegroundColor Yellow
  $targetArgs = @{
    Environment  = "Target"
    OutputRoot   = $OutputRoot
    Prefix       = "ADOnly"
    CustomerName = $CustomerName
  }
  if ($TargetServer) { $targetArgs['Server'] = $TargetServer }

  $targetRunResult = & $DiscoveryScriptPath @targetArgs
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
  # Generate analysis config file
  # ========================================
  $configPath = $null
  if (-not $SkipConfigFile) {
    $timestamp = Get-AdTimestamp -Format File
    $configPath = Join-Path $OutputRoot "AD__Discovery__Config__$timestamp.json"

    $config = [ordered]@{
      SourceRunRoot         = $sourceRunRoot
      TargetRunRoot         = $targetRunRoot
      CustomerName          = $CustomerName
      OutputRoot            = $OutputRoot
      GenerateLoeForBoth    = $false
      IncludeTargetPlanning = $false
      CollectedDate         = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
      SourceServer          = if ($SourceServer) { $SourceServer } else { "Default" }
      TargetServer          = if ($TargetServer) { $TargetServer } else { "Default" }
    }

    $config | ConvertTo-Json -Depth 5 | Out-File -FilePath $configPath -Encoding UTF8 -Force
    Write-Host "  [OK] Analysis config saved: $configPath" -ForegroundColor Green
    Write-Host ""
  }

  Write-Host ""
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host "[COMPLETE] Data Collection Complete" -ForegroundColor Green
  Write-Host "========================================" -ForegroundColor Cyan
  Write-Host ""

  # Print summary
  Write-Host "DISCOVERY DATA COLLECTED:" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "Source Environment:" -ForegroundColor Yellow
  Write-Host "  $sourceRunRoot" -ForegroundColor White
  Write-Host ""
  Write-Host "Target Environment:" -ForegroundColor Yellow
  Write-Host "  $targetRunRoot" -ForegroundColor White
  Write-Host ""

  if ($configPath) {
    Write-Host "Analysis Configuration:" -ForegroundColor Yellow
    Write-Host "  $configPath" -ForegroundColor White
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "  Run analysis using:" -ForegroundColor White
    Write-Host "    Invoke-AdDiscoveryAnalysis -ConfigFile '$configPath'" -ForegroundColor Green
    Write-Host ""
  } else {
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "  Run analysis using:" -ForegroundColor White
    Write-Host "    Invoke-AdDiscoveryAnalysis -SourceRunRoot '$sourceRunRoot' -TargetRunRoot '$targetRunRoot'" -ForegroundColor Green
    Write-Host ""
  }

  return [pscustomobject]@{
    SourceRunRoot = $sourceRunRoot
    TargetRunRoot = $targetRunRoot
    ConfigFile    = $configPath
  }
}
