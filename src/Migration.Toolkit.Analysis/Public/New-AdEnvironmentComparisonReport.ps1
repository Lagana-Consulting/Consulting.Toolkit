function New-AdEnvironmentComparisonReport {
  <#
  .SYNOPSIS
  Generate HTML and Excel reports comparing source vs target AD discovery outputs.

  .DESCRIPTION
  Compares discovery outputs from two environments (source and target) and generates:
  - HTML report with side-by-side metrics, identified conflicts, new objects in target, and missing objects
  - Excel workbook with detailed comparison sheets

  .PARAMETER SourceRunRoot
  Path to source environment discovery output root folder

  .PARAMETER TargetRunRoot
  Path to target environment discovery output root folder

  .PARAMETER OutputPath
  Path where HTML report will be saved. If not provided, uses RunRoot of source environment.

  .PARAMETER CustomerName
  Customer name to include in report header (optional)

  .EXAMPLE
  New-AdEnvironmentComparisonReport -SourceRunRoot "c:\reports\ADOnly_20260121-132028" -TargetRunRoot "c:\reports\ADOnly__target_20260121-143515"
  #>

  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$SourceRunRoot,

    [Parameter(Mandatory)]
    [string]$TargetRunRoot,

    [string]$OutputPath,
    [string]$CustomerName = "Organization"
  )

  if (-not (Test-Path -LiteralPath $SourceRunRoot)) {
    throw "Source run root not found: $SourceRunRoot"
  }
  if (-not (Test-Path -LiteralPath $TargetRunRoot)) {
    throw "Target run root not found: $TargetRunRoot"
  }

  # Determine output path
  if (-not $OutputPath) {
    $timestamp = (Get-AdTimestamp -Format File)
    $OutputPath = Join-Path $SourceRunRoot "AD__Environment__Comparison__Report__$timestamp.html"
  }

  # Helper function to safely import CSV
  function Import-CsvSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
      return @()
    }
    try {
      return @(Import-Csv -Path $Path -ErrorAction Stop)
    } catch {
      Write-Warning "Failed to import $Path : $_"
      return @()
    }
  }

  # Load assessment summaries
  $sourceAssessment = Import-CsvSafe (Join-Path $SourceRunRoot 'AD__Assessment__Summary__Forest.csv') | Select-Object -First 1
  $targetAssessment = Import-CsvSafe (Join-Path $TargetRunRoot 'AD__Assessment__Summary__Forest.csv') | Select-Object -First 1

  # Provide fallback if either is null
  if (-not $sourceAssessment) {
    $sourceAssessment = [pscustomobject]@{
      DomainsCount = 0; UsersTotal = 0; GroupsTotal = 0; ComputersTotal = 0; ForestName = 'Unknown'
    }
  }
  if (-not $targetAssessment) {
    $targetAssessment = [pscustomobject]@{
      DomainsCount = 0; UsersTotal = 0; GroupsTotal = 0; ComputersTotal = 0; ForestName = 'Unknown'
    }
  }

  # Load risk flags summary
  $sourceRiskFlags = Import-CsvSafe (Join-Path $SourceRunRoot 'AD__Migration__RiskFlagsSummary__Forest.csv')
  $targetRiskFlags = Import-CsvSafe (Join-Path $TargetRunRoot 'AD__Migration__RiskFlagsSummary__Forest.csv')

  # Load domain-level CSVs for each domain
  $sourceDomainDir = Join-Path $SourceRunRoot '20_domains'
  $targetDomainDir = Join-Path $TargetRunRoot '20_domains'

  $sourceDomainFolders = @(Get-ChildItem -Path $sourceDomainDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Domain-' })
  $targetDomainFolders = @(Get-ChildItem -Path $targetDomainDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Domain-' })

  # Extract domain names
  $sourceDomains = @($sourceDomainFolders | ForEach-Object { $_.Name -replace '^Domain-', '' } | Sort-Object)
  $targetDomains = @($targetDomainFolders | ForEach-Object { $_.Name -replace '^Domain-', '' } | Sort-Object)

  # Suppress warnings when source and target are the same path (single-environment mode)
  $isSameEnvironment = $SourceRunRoot -eq $TargetRunRoot

  $newDomains = @($targetDomains | Where-Object { $_ -notin $sourceDomains })
  $missingDomains = @($sourceDomains | Where-Object { $_ -notin $targetDomains })
  $commonDomains = @($sourceDomains | Where-Object { $_ -in $targetDomains })

  # Build domain comparison table (all domains from both environments)
  $allDomains = @(($sourceDomains + $targetDomains) | Sort-Object -Unique)
  $domainComparisons = @()
  foreach ($domain in $allDomains) {
    $sourceFolder = Join-Path $sourceDomainDir "Domain-$domain"
    $targetFolder = Join-Path $targetDomainDir "Domain-$domain"

    # Use Get-ChildItem to find files, then import
    $sourceUsersFile = Get-ChildItem -Path $sourceFolder -Filter '*Identity__Users*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $targetUsersFile = Get-ChildItem -Path $targetFolder -Filter '*Identity__Users*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $sourceUsers = if ($sourceUsersFile) { (Import-CsvSafe $sourceUsersFile.FullName | Measure-Object).Count } else { 0 }
    $targetUsers = if ($targetUsersFile) { (Import-CsvSafe $targetUsersFile.FullName | Measure-Object).Count } else { 0 }

    $sourceGroupsFile = Get-ChildItem -Path $sourceFolder -Filter '*Identity__Groups*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $targetGroupsFile = Get-ChildItem -Path $targetFolder -Filter '*Identity__Groups*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $sourceGroups = if ($sourceGroupsFile) { (Import-CsvSafe $sourceGroupsFile.FullName | Measure-Object).Count } else { 0 }
    $targetGroups = if ($targetGroupsFile) { (Import-CsvSafe $targetGroupsFile.FullName | Measure-Object).Count } else { 0 }

    $sourceComputersFile = Get-ChildItem -Path $sourceFolder -Filter '*Identity__ComputersAll*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $targetComputersFile = Get-ChildItem -Path $targetFolder -Filter '*Identity__ComputersAll*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $sourceComputers = if ($sourceComputersFile) { (Import-CsvSafe $sourceComputersFile.FullName | Measure-Object).Count } else { 0 }
    $targetComputers = if ($targetComputersFile) { (Import-CsvSafe $targetComputersFile.FullName | Measure-Object).Count } else { 0 }

    $sourceSpnsFile = Get-ChildItem -Path $sourceFolder -Filter '*Identity__SPNs*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $targetSpnsFile = Get-ChildItem -Path $targetFolder -Filter '*Identity__SPNs*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $sourceSpns = if ($sourceSpnsFile) { (Import-CsvSafe $sourceSpnsFile.FullName | Measure-Object).Count } else { 0 }
    $targetSpns = if ($targetSpnsFile) { (Import-CsvSafe $targetSpnsFile.FullName | Measure-Object).Count } else { 0 }

    $sourceOusFile = Get-ChildItem -Path $sourceFolder -Filter '*Identity__OrganizationalUnits*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $targetOusFile = Get-ChildItem -Path $targetFolder -Filter '*Identity__OrganizationalUnits*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $sourceOus = if ($sourceOusFile) { (Import-CsvSafe $sourceOusFile.FullName | Measure-Object).Count } else { 0 }
    $targetOus = if ($targetOusFile) { (Import-CsvSafe $targetOusFile.FullName | Measure-Object).Count } else { 0 }

    $domainComparisons += [pscustomobject]@{
      Domain          = $domain
      SourceUsers     = $sourceUsers
      TargetUsers     = $targetUsers
      UserDelta       = $targetUsers - $sourceUsers
      SourceGroups    = $sourceGroups
      TargetGroups    = $targetGroups
      GroupDelta      = $targetGroups - $sourceGroups
      SourceComputers = $sourceComputers
      TargetComputers = $targetComputers
      ComputerDelta   = $targetComputers - $sourceComputers
      SourceSpns      = $sourceSpns
      TargetSpns      = $targetSpns
      SpnDelta        = $targetSpns - $sourceSpns
      SourceOus       = $sourceOus
      TargetOus       = $targetOus
      OuDelta         = $targetOus - $sourceOus
    }
  }

  # Build metrics comparison
  $metrics = @(
    @{ Name = "Forest Domains"; Source = $sourceAssessment.DomainsCount; Target = $targetAssessment.DomainsCount }
    @{ Name = "Total Users"; Source = $sourceAssessment.UsersTotal; Target = $targetAssessment.UsersTotal }
    @{ Name = "Total Groups"; Source = $sourceAssessment.GroupsTotal; Target = $targetAssessment.GroupsTotal }
    @{ Name = "Total Computers"; Source = $sourceAssessment.ComputersTotal; Target = $targetAssessment.ComputersTotal }
    @{ Name = "Domain Trusts"; Source = $sourceAssessment.DomainsCount; Target = $targetAssessment.DomainsCount }
  ) | ForEach-Object {
    $delta = [int]$_.Target - [int]$_.Source
    $_ | Add-Member -NotePropertyName Delta -NotePropertyValue $delta -PassThru
  }

  # Build HTML without here-strings (to avoid parser errors)
  $htmlHeader = @(
    "<!DOCTYPE html>",
    "<html lang=`"en`">",
    "<head>",
    "  <meta charset=`"UTF-8`">",
    "  <meta name=`"viewport`" content=`"width=device-width, initial-scale=1.0`">",
    "  <title>AD Migration Comparison Report</title>",
    "  <style>",
    "    * { margin: 0; padding: 0; box-sizing: border-box; }",
    "    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; color: #333; line-height: 1.6; }",
    "    .container { max-width: 1200px; margin: 0 auto; padding: 20px; background: white; box-shadow: 0 0 10px rgba(0,0,0,0.1); }",
    "    header { border-bottom: 4px solid #0078d4; padding-bottom: 20px; margin-bottom: 30px; }",
    "    h1 { color: #0078d4; font-size: 28px; margin-bottom: 5px; }",
    "    .subtitle { color: #666; font-size: 14px; }",
    "    .section { margin-bottom: 40px; }",
    "    .section h2 { color: #0078d4; font-size: 20px; margin: 20px 0 15px 0; border-left: 4px solid #0078d4; padding-left: 10px; }",
    "    table { width: 100%; border-collapse: collapse; margin: 15px 0; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }",
    "    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }",
    "    th { background: #f0f0f0; font-weight: 600; color: #333; }",
    "    tr:hover { background: #f9f9f9; }",
    "    .positive { color: #107c10; font-weight: 600; }",
    "    .negative { color: #d83b01; font-weight: 600; }",
    "    .neutral { color: #666; }",
    "    .warning { background: #fff4ce; color: #9d5d00; padding: 10px; margin: 10px 0; border-left: 4px solid #ffc107; border-radius: 3px; }",
    "    .info-box { background: #eff6fc; color: #003366; padding: 15px; margin: 15px 0; border-left: 4px solid #0078d4; border-radius: 3px; }",
    "    .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin: 15px 0; }",
    "    .metric-card { background: #f0f0f0; padding: 15px; border-radius: 5px; border-left: 4px solid #0078d4; }",
    "    .metric-card .label { font-size: 12px; color: #666; text-transform: uppercase; }",
    "    .metric-card .value { font-size: 24px; font-weight: 700; color: #333; margin-top: 5px; }",
    "    .metric-card .delta { font-size: 12px; margin-top: 5px; }",
    "    footer { border-top: 1px solid #ddd; padding-top: 15px; margin-top: 30px; text-align: center; color: #999; font-size: 12px; }",
    "  </style>",
    "</head>",
    "<body>",
    "  <div class=`"container`">",
    "    <header>",
    "      <h1>AD Environment Comparison Report</h1>",
    "      <p class=`"subtitle`">$CustomerName | Generated $(Get-Date -Format 'MMMM d, yyyy HH:mm:ss')</p>",
    "    </header>",
    "",
    "    <div class=`"section`">",
    "      <h2>Executive Summary</h2>",
    "      <div class=`"info-box`">",
    "        <strong>Comparison Summary:</strong><br/>",
    "        Source Environment: $SourceRunRoot<br/>",
    "        Target Environment: $TargetRunRoot",
    "      </div>"
  )

  $htmlContent = ($htmlHeader -join "`n")

  # Only show domain mismatch warnings if comparing different environments
  if (-not $isSameEnvironment) {
    if ($newDomains.Count -gt 0) {
      $htmlContent += "<div class='warning'><strong>WARNING - New Domains in Target:</strong> $($newDomains -join ', ')</div>"
    }
    if ($missingDomains.Count -gt 0) {
      $htmlContent += "<div class='warning'><strong>WARNING - Domains Missing from Target:</strong> $($missingDomains -join ', ')</div>"
    }
  }

  $htmlContent += "
    </div>

    <div class='section'>
      <h2>Forest-Level Metrics</h2>
      <div class='metrics-grid'>
"

  foreach ($metric in $metrics) {
    $deltaClass = if ($metric.Delta -gt 0) { 'positive' } elseif ($metric.Delta -lt 0) { 'negative' } else { 'neutral' }
    $deltaSymbol = if ($metric.Delta -gt 0) { '&uarr;' } elseif ($metric.Delta -lt 0) { '&darr;' } else { '=' }
    $htmlContent += "
      <div class='metric-card'>
        <div class='label'>$($metric.Name)</div>
        <div class='value'>$($metric.Target)</div>
        <div class='delta'><span class='$deltaClass'>$deltaSymbol $($metric.Delta) (Source: $($metric.Source))</span></div>
      </div>
"
  }

  $htmlContent += "
      </div>
    </div>

    <div class='section'>
      <h2>Domain-Level Comparison</h2>
      <table>
        <thead>
          <tr>
            <th rowspan='2'>Domain</th>
            <th colspan='3'>Users</th>
            <th colspan='3'>Groups</th>
            <th colspan='3'>Computers</th>
            <th colspan='3'>SPNs</th>
            <th colspan='3'>OUs</th>
          </tr>
          <tr>
            <th>Source</th>
            <th>Target</th>
            <th>Delta</th>
            <th>Source</th>
            <th>Target</th>
            <th>Delta</th>
            <th>Source</th>
            <th>Target</th>
            <th>Delta</th>
            <th>Source</th>
            <th>Target</th>
            <th>Delta</th>
            <th>Source</th>
            <th>Target</th>
            <th>Delta</th>
          </tr>
        </thead>
        <tbody>
"

  foreach ($comp in $domainComparisons) {
    $userDeltaClass = if ($comp.UserDelta -gt 0) { 'positive' } elseif ($comp.UserDelta -lt 0) { 'negative' } else { 'neutral' }
    $groupDeltaClass = if ($comp.GroupDelta -gt 0) { 'positive' } elseif ($comp.GroupDelta -lt 0) { 'negative' } else { 'neutral' }
    $computerDeltaClass = if ($comp.ComputerDelta -gt 0) { 'positive' } elseif ($comp.ComputerDelta -lt 0) { 'negative' } else { 'neutral' }
    $spnDeltaClass = if ($comp.SpnDelta -gt 0) { 'positive' } elseif ($comp.SpnDelta -lt 0) { 'negative' } else { 'neutral' }
    $ouDeltaClass = if ($comp.OuDelta -gt 0) { 'positive' } elseif ($comp.OuDelta -lt 0) { 'negative' } else { 'neutral' }

    $htmlContent += "
          <tr>
            <td><strong>$($comp.Domain)</strong></td>
            <td>$($comp.SourceUsers)</td>
            <td>$($comp.TargetUsers)</td>
            <td><span class='$userDeltaClass'>$($comp.UserDelta)</span></td>
            <td>$($comp.SourceGroups)</td>
            <td>$($comp.TargetGroups)</td>
            <td><span class='$groupDeltaClass'>$($comp.GroupDelta)</span></td>
            <td>$($comp.SourceComputers)</td>
            <td>$($comp.TargetComputers)</td>
            <td><span class='$computerDeltaClass'>$($comp.ComputerDelta)</span></td>
            <td>$($comp.SourceSpns)</td>
            <td>$($comp.TargetSpns)</td>
            <td><span class='$spnDeltaClass'>$($comp.SpnDelta)</span></td>
            <td>$($comp.SourceOus)</td>
            <td>$($comp.TargetOus)</td>
            <td><span class='$ouDeltaClass'>$($comp.OuDelta)</span></td>
          </tr>
"
  }

  $footer = @(
    "        </tbody>",
    "      </table>",
    "    </div>",
    "",
    "    <div class='section'>",
    "      <h2>Next Steps</h2>",
    "      <ol style='margin-left: 20px;'>",
    "        <li>Review domain-level deltas to identify migration gaps</li>",
    "        <li>Investigate new domains in target and verify they are expected</li>",
    "        <li>Run readiness checklist to validate migration prerequisites</li>",
    "        <li>Execute detailed comparison via Excel workbook for full object-level analysis</li>",
    "      </ol>",
    "    </div>",
    "",
    "    <footer>",
    "      <p>Paul Lagana Toolkit | Migration Readiness Assessment</p>",
    "    </footer>",
    "  </div>",
    "</body>",
    "</html>"
  )

  $htmlContent += ("`n" + ($footer -join "`n"))

  # Save HTML
  $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
  Write-Host "Comparison report generated: $OutputPath" -ForegroundColor Green

  return [pscustomobject]@{
    ReportPath        = $OutputPath
    SourceEnvironment = 'Source'
    TargetEnvironment = 'Target'
    SourceDomains     = $sourceDomains
    TargetDomains     = $targetDomains
    NewDomains        = $newDomains
    MissingDomains    = $missingDomains
    DomainComparisons = $domainComparisons
  }
}
