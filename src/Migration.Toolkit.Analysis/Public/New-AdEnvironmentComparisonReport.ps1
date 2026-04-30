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

  $outputDirectory = Split-Path -Parent $OutputPath
  if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
  }

  function ConvertTo-HtmlText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
  }

  function Get-AdMailDomains {
    param([AllowEmptyCollection()][array]$Records)

    $domains = New-Object System.Collections.Generic.List[string]

    foreach ($record in @($Records)) {
      $mail = [string]$record.Mail
      if ([string]::IsNullOrWhiteSpace($mail) -or $mail -notmatch '@') { continue }

      $domain = ($mail.Split('@')[-1]).Trim().ToLowerInvariant()
      if (-not [string]::IsNullOrWhiteSpace($domain) -and -not $domains.Contains($domain)) {
        $domains.Add($domain)
      }
    }

    return @($domains | Sort-Object)
  }

  function Get-AdMailDomainRecordsFromRunRoot {
    param([Parameter(Mandatory)][string]$RunRoot)

    $records = @()
    $domainRoot = Join-Path $RunRoot '20_domains'
    if (-not (Test-Path -LiteralPath $domainRoot -PathType Container)) {
      return @()
    }

    $patterns = @(
      'AD__Domain__Identity__Users__*.csv',
      'AD__Domain__Identity__Groups__*.csv',
      'AD__Domain__Directory__Contacts__*.csv'
    )

    foreach ($domainFolder in @(Get-ChildItem -LiteralPath $domainRoot -Directory -ErrorAction SilentlyContinue)) {
      foreach ($pattern in $patterns) {
        foreach ($file in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter $pattern -File -ErrorAction SilentlyContinue)) {
          $records += @(Import-Csv -LiteralPath $file.FullName -ErrorAction SilentlyContinue)
        }
      }
    }

    return @($records)
  }

  $sourceData = Get-AdDiscoveryRunSummary -RunRoot $SourceRunRoot
  $targetData = Get-AdDiscoveryRunSummary -RunRoot $TargetRunRoot

  $sourceAssessment = $sourceData.Summary
  $targetAssessment = $targetData.Summary
  $sourceRiskFlags = @($sourceData.RiskSummary)
  $targetRiskFlags = @($targetData.RiskSummary)

  $sourceDomains = @($sourceData.DomainSummaries | ForEach-Object { $_.Domain } | Sort-Object)
  $targetDomains = @($targetData.DomainSummaries | ForEach-Object { $_.Domain } | Sort-Object)

  # Suppress warnings when source and target are the same path (single-environment mode)
  $isSameEnvironment = $SourceRunRoot -eq $TargetRunRoot

  $duplicateConflicts = @()
  $duplicateCsvPath = $null
  $duplicateCountsByType = @()
  $duplicateUserConflictCount = 0
  $duplicateGroupConflictCount = 0
  $duplicateComputerConflictCount = 0
  $identityConflictBreakdown = [ordered]@{
    SamAccountName         = 0
    UserPrincipalName      = 0
    UserPrincipalNameLocal = 0
    Mail                   = 0
    MailLocal              = 0
  }
  $groupConflictCount = 0

  $sourceUpnSuffixValues = @(
    @($sourceData.UpnSuffixes) |
      ForEach-Object { [string]$_.Suffix } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { $_.Trim().ToLowerInvariant() } |
      Sort-Object -Unique
  )
  $targetUpnSuffixValues = @(
    @($targetData.UpnSuffixes) |
      ForEach-Object { [string]$_.Suffix } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      ForEach-Object { $_.Trim().ToLowerInvariant() } |
      Sort-Object -Unique
  )

  $sourceMailDomains = @(Get-AdMailDomains -Records (Get-AdMailDomainRecordsFromRunRoot -RunRoot $SourceRunRoot))
  $targetMailDomains = @(Get-AdMailDomains -Records (Get-AdMailDomainRecordsFromRunRoot -RunRoot $TargetRunRoot))
  $sharedUpnSuffixes = @($sourceUpnSuffixValues | Where-Object { $targetUpnSuffixValues -contains $_ } | Sort-Object -Unique)
  $sourceOnlyUpnSuffixes = @($sourceUpnSuffixValues | Where-Object { $targetUpnSuffixValues -notcontains $_ } | Sort-Object -Unique)
  $sharedMailDomains = @($sourceMailDomains | Where-Object { $targetMailDomains -contains $_ } | Sort-Object -Unique)
  $sourceOnlyMailDomains = @($sourceMailDomains | Where-Object { $targetMailDomains -notcontains $_ } | Sort-Object -Unique)

  $newDomains = @($targetDomains | Where-Object { $_ -notin $sourceDomains })
  $missingDomains = @($sourceDomains | Where-Object { $_ -notin $targetDomains })
  $commonDomains = @($sourceDomains | Where-Object { $_ -in $targetDomains })

  if (-not $isSameEnvironment) {
    $duplicateConflicts = @(
      Invoke-AdCrossForestDuplicateCheck `
        -SourceRunRoots @($SourceRunRoot) `
        -TargetRunRoot $TargetRunRoot `
        -OutputRoot $outputDirectory `
        -PassThru
    )

    if ($duplicateConflicts.Count -gt 0) {
      $duplicateCsvPath = Join-Path $outputDirectory ([System.IO.Path]::GetFileNameWithoutExtension($OutputPath) + '__DuplicateConflicts.csv')
      $duplicateConflicts |
        Select-Object ConflictType, ConflictValue, ObjectClasses, ConflictCount, ConflictingDomains, ConflictingDNs, Severity, Recommendation |
        Export-Csv -LiteralPath $duplicateCsvPath -NoTypeInformation -Encoding UTF8 -Force

      $duplicateCountsByType = @(
        $duplicateConflicts |
          Group-Object -Property ConflictType |
          Sort-Object Count -Descending |
          ForEach-Object {
            [pscustomobject]@{
              ConflictType = $_.Name
              Count        = $_.Count
            }
          }
      )

      $duplicateUserConflictCount = @($duplicateConflicts | Where-Object { [string]$_.ObjectClasses -match 'user' }).Count
      $duplicateGroupConflictCount = @($duplicateConflicts | Where-Object { [string]$_.ObjectClasses -match 'group' }).Count
      $duplicateComputerConflictCount = @($duplicateConflicts | Where-Object { [string]$_.ObjectClasses -match 'computer' }).Count
      $groupConflictCount = @($duplicateConflicts | Where-Object { [string]$_.ObjectClasses -match 'group' -and [string]$_.ConflictType -in @('SamAccountName', 'Mail', 'MailLocal') }).Count

      foreach ($conflictType in @($identityConflictBreakdown.Keys)) {
        $identityConflictBreakdown[$conflictType] = @($duplicateConflicts | Where-Object { [string]$_.ConflictType -eq $conflictType }).Count
      }
    }
  }

  $upnConflictCount = [int]$identityConflictBreakdown.UserPrincipalName + [int]$identityConflictBreakdown.UserPrincipalNameLocal
  $smtpConflictCount = [int]$identityConflictBreakdown.Mail + [int]$identityConflictBreakdown.MailLocal
  $samConflictCount = [int]$identityConflictBreakdown.SamAccountName
  $nonRoutableUpnCount = [int]$sourceAssessment.UsersNonRoutableUPNCount

  $identityTransformationNotes = New-Object System.Collections.Generic.List[string]
  if ($nonRoutableUpnCount -gt 0) {
    $identityTransformationNotes.Add("$nonRoutableUpnCount source account(s) use non-routable UPN suffixes and should be normalized to routable domains before migration.")
  }
  if ($upnConflictCount -gt 0) {
    $identityTransformationNotes.Add("$upnConflictCount UPN-based conflict(s) were identified, so UPN changes or match exceptions will be required before cutover.")
  }
  if ($sourceOnlyUpnSuffixes.Count -gt 0) {
    $identityTransformationNotes.Add("Source-only UPN suffixes were identified: $($sourceOnlyUpnSuffixes -join ', '). These suffixes should be added to the target or remapped during migration planning.")
  }
  if ($smtpConflictCount -gt 0) {
    $identityTransformationNotes.Add("$smtpConflictCount SMTP-related conflict(s) were identified and should be resolved before soft matching or mail routing changes are attempted.")
  }
  if ($sourceOnlyMailDomains.Count -gt 0) {
    $identityTransformationNotes.Add("Source-only SMTP domains were identified: $($sourceOnlyMailDomains -join ', '). Validate ownership, accepted domains, and target namespace alignment before migration waves begin.")
  }
  if ($samConflictCount -gt 0) {
    $identityTransformationNotes.Add("$samConflictCount sAMAccountName conflict(s) were identified and will require renaming, consolidation, or exception handling before migration execution.")
  }
  if ($identityTransformationNotes.Count -eq 0) {
    $identityTransformationNotes.Add('No immediate UPN, SMTP, or sAMAccountName transformations were flagged by the automated comparison. Namespace validation should still be confirmed during wave planning.')
  }

  # Build domain comparison table (all domains from both environments)
  $allDomains = @(($sourceDomains + $targetDomains) | Sort-Object -Unique)
  $domainComparisons = @()
  foreach ($domain in $allDomains) {
    $sourceDomain = @($sourceData.DomainSummaries | Where-Object { $_.Domain -eq $domain } | Select-Object -First 1)
    $targetDomain = @($targetData.DomainSummaries | Where-Object { $_.Domain -eq $domain } | Select-Object -First 1)

    $sourceSummary = if ($sourceDomain.Count -gt 0) { $sourceDomain[0].Summary } else { $null }
    $targetSummary = if ($targetDomain.Count -gt 0) { $targetDomain[0].Summary } else { $null }

    $sourceUsers = if ($sourceSummary) { [int]$sourceSummary.UsersTotal } else { 0 }
    $targetUsers = if ($targetSummary) { [int]$targetSummary.UsersTotal } else { 0 }
    $sourceGroups = if ($sourceSummary) { [int]$sourceSummary.GroupsTotal } else { 0 }
    $targetGroups = if ($targetSummary) { [int]$targetSummary.GroupsTotal } else { 0 }
    $sourceComputers = if ($sourceSummary) { [int]$sourceSummary.ComputersTotal } else { 0 }
    $targetComputers = if ($targetSummary) { [int]$targetSummary.ComputersTotal } else { 0 }
    $sourceSpns = if ($sourceSummary) { [int]$sourceSummary.SpnCount } else { 0 }
    $targetSpns = if ($targetSummary) { [int]$targetSummary.SpnCount } else { 0 }
    $sourceOus = if ($sourceSummary) { [int]$sourceSummary.OuCount } else { 0 }
    $targetOus = if ($targetSummary) { [int]$targetSummary.OuCount } else { 0 }

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
    @{ Name = "Forest Trusts"; Source = $sourceAssessment.TrustCount; Target = $targetAssessment.TrustCount }
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
      <h2>Duplicate and Collision Check</h2>
"

  if ($isSameEnvironment) {
    $htmlContent += "
      <div class='info-box'>
        Duplicate checking was skipped because the source and target paths are the same environment.
      </div>
"
  }
  elseif ($duplicateConflicts.Count -gt 0) {
    $duplicateCsvFile = Split-Path -Leaf $duplicateCsvPath
    $htmlContent += "
      <div class='warning'>
        <strong>Duplicate objects detected:</strong> $($duplicateConflicts.Count) source-to-target conflicts were identified.
        <br/>Supporting CSV: <a href='$duplicateCsvFile'>$duplicateCsvFile</a>
      </div>
      <div class='metrics-grid'>
        <div class='metric-card'>
          <div class='label'>Total Conflicts</div>
          <div class='value'>$($duplicateConflicts.Count)</div>
          <div class='delta'>Source-to-target duplicate matches</div>
        </div>
        <div class='metric-card'>
          <div class='label'>User Conflicts</div>
          <div class='value'>$duplicateUserConflictCount</div>
          <div class='delta'>Conflicts involving user objects</div>
        </div>
        <div class='metric-card'>
          <div class='label'>Group Conflicts</div>
          <div class='value'>$duplicateGroupConflictCount</div>
          <div class='delta'>Conflicts involving group objects</div>
        </div>
        <div class='metric-card'>
          <div class='label'>Computer Conflicts</div>
          <div class='value'>$duplicateComputerConflictCount</div>
          <div class='delta'>Conflicts involving computer objects</div>
        </div>
      </div>
      <table>
        <thead>
          <tr>
            <th>Conflict Type</th>
            <th>Count</th>
          </tr>
        </thead>
        <tbody>
"

    foreach ($dupType in $duplicateCountsByType) {
      $htmlContent += "
          <tr>
            <td>$($dupType.ConflictType)</td>
            <td>$($dupType.Count)</td>
          </tr>
"
    }

    $htmlContent += "
        </tbody>
      </table>
"
  }
  else {
    $htmlContent += "
      <div class='info-box'>
        No duplicate source-to-target user, group, or computer identifiers were detected by the automated cross-forest duplicate check.
      </div>
"
  }

  $htmlContent += "
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

  $htmlContent += "
    </div>

    <div class='section'>
      <h2>Identity Matching and Conflict Analysis</h2>
"

  if ($isSameEnvironment) {
    $htmlContent += "
      <div class='info-box'>
        Identity conflict analysis was skipped because the source and target paths are the same environment.
      </div>
"
  }
  else {
    $sourceUpnSuffixText = if ($sourceUpnSuffixValues.Count -gt 0) { $sourceUpnSuffixValues -join ', ' } else { 'None exported in this source run' }
    $targetUpnSuffixText = if ($targetUpnSuffixValues.Count -gt 0) { $targetUpnSuffixValues -join ', ' } else { 'None exported in this target run' }
    $sourceMailDomainText = if ($sourceMailDomains.Count -gt 0) { $sourceMailDomains -join ', ' } else { 'No SMTP domains were discovered from exported mail-enabled objects' }
    $targetMailDomainText = if ($targetMailDomains.Count -gt 0) { $targetMailDomains -join ', ' } else { 'No SMTP domains were discovered from exported mail-enabled objects' }
    $sharedUpnSuffixText = if ($sharedUpnSuffixes.Count -gt 0) { $sharedUpnSuffixes -join ', ' } else { 'No shared UPN suffixes were identified from the exported suffix lists' }
    $sharedMailDomainText = if ($sharedMailDomains.Count -gt 0) { $sharedMailDomains -join ', ' } else { 'No shared SMTP domains were identified from exported mail addresses' }

    $htmlContent += "
      <div class='info-box'>
        This section highlights the identity attributes most likely to affect matching, namespace alignment, and pre-migration remediation across the source and target environments.
      </div>
      <div class='metrics-grid'>
        <div class='metric-card'>
          <div class='label'>UPN Conflicts</div>
          <div class='value'>$upnConflictCount</div>
          <div class='delta'>$([int]$identityConflictBreakdown.UserPrincipalName) exact match(es), $([int]$identityConflictBreakdown.UserPrincipalNameLocal) local-part overlap(s)</div>
        </div>
        <div class='metric-card'>
          <div class='label'>SMTP Conflicts</div>
          <div class='value'>$smtpConflictCount</div>
          <div class='delta'>$([int]$identityConflictBreakdown.Mail) exact match(es), $([int]$identityConflictBreakdown.MailLocal) local-part overlap(s)</div>
        </div>
        <div class='metric-card'>
          <div class='label'>sAMAccountName Conflicts</div>
          <div class='value'>$samConflictCount</div>
          <div class='delta'>Cross-environment naming conflicts across users, groups, or computers</div>
        </div>
        <div class='metric-card'>
          <div class='label'>Group Naming Conflicts</div>
          <div class='value'>$groupConflictCount</div>
          <div class='delta'>Conflicts involving group names or mail-enabled group addresses</div>
        </div>
      </div>
      <table>
        <thead>
          <tr>
            <th>Match Area</th>
            <th>Current Signal</th>
            <th>What It Means for Migration</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>Soft Match</strong></td>
            <td>UPN and SMTP comparisons are available from the AD discovery output.</td>
            <td>Use UPN and SMTP conflicts to validate namespace alignment and plan for accounts that may need renaming or exception handling before synchronization or coexistence.</td>
          </tr>
          <tr>
            <td><strong>Hard Match</strong></td>
            <td>ImmutableID / sourceAnchor values were not collected in this AD-only assessment.</td>
            <td>Hard-match planning should be completed separately if hybrid identity or existing cloud identity reconciliation is part of the migration scope.</td>
          </tr>
          <tr>
            <td><strong>Display Name Conflicts</strong></td>
            <td>Not included in the current automated conflict set.</td>
            <td>Display-name review can still be useful for user experience and address book cleanup, but it is lower priority than UPN, SMTP, and sign-in identifier alignment.</td>
          </tr>
          <tr>
            <td><strong>Teams / M365 Group Conflicts</strong></td>
            <td>Not assessed from the current on-premises AD-only discovery output.</td>
            <td>Cloud group and collaboration conflict analysis requires Entra ID / Microsoft 365 data and should be assessed separately when that workload is in scope.</td>
          </tr>
        </tbody>
      </table>
      <table>
        <thead>
          <tr>
            <th>Namespace Area</th>
            <th>Source</th>
            <th>Target</th>
            <th>Shared / Overlap</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td><strong>UPN Suffixes</strong></td>
            <td>$(ConvertTo-HtmlText $sourceUpnSuffixText)</td>
            <td>$(ConvertTo-HtmlText $targetUpnSuffixText)</td>
            <td>$(ConvertTo-HtmlText $sharedUpnSuffixText)</td>
          </tr>
          <tr>
            <td><strong>SMTP Domains</strong></td>
            <td>$(ConvertTo-HtmlText $sourceMailDomainText)</td>
            <td>$(ConvertTo-HtmlText $targetMailDomainText)</td>
            <td>$(ConvertTo-HtmlText $sharedMailDomainText)</td>
          </tr>
        </tbody>
      </table>
      <h3 style='margin: 15px 0 10px 0; color: #333;'>Required Transformations</h3>
      <ul style='margin-left: 20px;'>
"

    foreach ($note in $identityTransformationNotes) {
      $htmlContent += "
        <li>$(ConvertTo-HtmlText $note)</li>
"
    }

    if ($duplicateCsvPath) {
      $duplicateCsvFile = Split-Path -Leaf $duplicateCsvPath
      $htmlContent += "
      </ul>
      <p style='margin-top: 12px;'><strong>Supporting data:</strong> The detailed conflict export is available here: <a href='$duplicateCsvFile'>$duplicateCsvFile</a></p>
"
    }
    else {
      $htmlContent += "
      </ul>
"
    }
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
    "        <li>Review duplicate and collision results to resolve conflicting identities before migration waves begin</li>",
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
    DuplicateConflictCount = @($duplicateConflicts).Count
    DuplicateCsvPath       = $duplicateCsvPath
  }
}
