function Add-AzMailboxSummary {
  <#
  .SYNOPSIS
  Creates an Exchange mailbox summary table with storage metrics and top 10 largest mailboxes.

  .DESCRIPTION
  Analyzes Exchange mailbox CSV data to calculate total storage, average/largest mailbox sizes,
  and produces a secondary table showing the top 10 largest mailboxes.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to Exchange mailbox CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .EXAMPLE
  Add-AdMailboxSummary -Document $doc -Title "Mailbox Summary" -CsvPath "Mailboxes.csv" -TableStyleName "Light Grid Accent 1"
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Document,
    [Parameter(Mandatory)][string] $Title,
    [Parameter(Mandatory)][string] $CsvPath,
    [Parameter(Mandatory)][string] $TableStyleName,
    $InsertRange = $null,
    [string] $HeaderFontColor
  )

  if (-not (Test-Path $CsvPath)) {
    Write-Warning "Mailbox CSV not found: $CsvPath"
    return $InsertRange
  }

  $mailboxes = Import-Csv $CsvPath
  if ($mailboxes.Count -eq 0) {
    Write-Warning "Mailbox CSV '$CsvPath' is empty."
    return $InsertRange
  }

  # Helpers
  function Sum-ColumnAsInt64 {
    param([array]$Rows, [string]$ColumnName)
    $sum = [int64]0
    foreach ($row in $Rows) {
      [int64]$val = 0
      if ([int64]::TryParse([string]$row.$ColumnName, [ref]$val)) { $sum += $val }
    }
    return $sum
  }

  function Format-BytesHumanReadable {
    param([int64] $Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    elseif ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    else { return "{0:N2} KB" -f ($Bytes / 1KB) }
  }

  function Test-Truthy($Value) {
    if ($null -eq $Value) { return $false }
    $s = ([string]$Value).Trim()
    return @('true', '1', 'yes', 'y') -contains $s.ToLowerInvariant()
  }

  # Active vs deleted
  $activeMailboxes = $mailboxes | Where-Object { $_.'Is Deleted' -ne "True" }
  $deletedMailboxes = $mailboxes | Where-Object { $_.'Is Deleted' -eq "True" }

  $totalActive = $activeMailboxes.Count
  $totalDeleted = $deletedMailboxes.Count

  # Totals
  $totalItems = Sum-ColumnAsInt64 -Rows $activeMailboxes -ColumnName 'Item Count'
  $totalDeletedItems = Sum-ColumnAsInt64 -Rows $activeMailboxes -ColumnName 'Deleted Item Count'
  $totalStorageBytes = Sum-ColumnAsInt64 -Rows $activeMailboxes -ColumnName 'Storage Used (Byte)'

  $totalStorageFormatted = Format-BytesHumanReadable -Bytes $totalStorageBytes

  # Average & largest size
  $sizesBytes = @()
  foreach ($mbx in $activeMailboxes) {
    [int64]$val = 0
    if ([int64]::TryParse([string]$mbx.'Storage Used (Byte)', [ref]$val)) { $sizesBytes += $val }
  }

  $avgSizeFormatted = if ($sizesBytes.Count -gt 0) {
    Format-BytesHumanReadable -Bytes ([int64]($sizesBytes | Measure-Object -Average).Average)
  } else { "N/A" }

  $maxSizeBytes = if ($sizesBytes.Count -gt 0) {
    [int64]($sizesBytes | Measure-Object -Maximum).Maximum
  } else { 0 }

  $maxSizeFormatted = if ($maxSizeBytes -gt 0) {
    Format-BytesHumanReadable -Bytes $maxSizeBytes
  } else { "N/A" }

  # Size bands
  $threshold50GB = 50GB
  $threshold1GB = 1GB

  $over50GB = ($activeMailboxes | Where-Object {
    [int64]$val = 0
    [int64]::TryParse([string]$_.'Storage Used (Byte)', [ref]$val) -and
    $val -ge $threshold50GB
  }).Count

  $under1GB = ($activeMailboxes | Where-Object {
    [int64]$val = 0
    [int64]::TryParse([string]$_.'Storage Used (Byte)', [ref]$val) -and
    $val -lt $threshold1GB
  }).Count

  # Activity / age
  $now = Get-Date

  $inactive90 = ($activeMailboxes | Where-Object {
    $_.'Last Activity Date' -and
    ((Get-Date $_.'Last Activity Date') -lt $now.AddDays(-90))
  }).Count

  $created30 = ($activeMailboxes | Where-Object {
    $_.'Created Date' -and
    ((Get-Date $_.'Created Date') -gt $now.AddDays(-30))
  }).Count

  # Recipient type + archive counts
  $hasRecipientType = ($mailboxes.Count -gt 0) -and ($mailboxes[0].PSObject.Properties.Name -contains 'Recipient Type')
  $hasArchive = ($mailboxes.Count -gt 0) -and ($mailboxes[0].PSObject.Properties.Name -contains 'Has Archive')

  $totalArchiveMailboxes = if ($hasArchive) {
    ($activeMailboxes | Where-Object { Test-Truthy $_.'Has Archive' }).Count
  } else { "" }

  $totalUserMailboxes = if ($hasRecipientType) {
    ($activeMailboxes | Where-Object { ([string]$_.'Recipient Type').Trim() -eq 'User' }).Count
  } else { "" }

  $totalSharedMailboxes = if ($hasRecipientType) {
    ($activeMailboxes | Where-Object { ([string]$_.'Recipient Type').Trim() -eq 'Shared' }).Count
  } else { "" }

  # Summary table
  $summary = [ordered]@{
    "Total Mailboxes"                            = $totalActive
    "Deleted Mailboxes"                          = $totalDeleted
    "Total Archive Mailboxes"                    = $totalArchiveMailboxes
    "Total User Mailboxes"                       = $totalUserMailboxes
    "Total Shared Mailboxes"                     = $totalSharedMailboxes
    "Total Item Count"                           = $totalItems
    "Total Deleted Item Count"                   = $totalDeletedItems
    "Total Storage Used"                         = $totalStorageFormatted
    "Average Mailbox Size"                       = $avgSizeFormatted
    "Largest Mailbox Size"                       = $maxSizeFormatted
    "Mailboxes ≥ 50 GB"                          = $over50GB
    "Mailboxes < 1 GB"                           = $under1GB
    "Inactive Mailboxes (> 90 days no activity)" = $inactive90
    "Mailboxes Created in Last 30 Days"          = $created30
  }

  $currentRange = Add-AdSimpleSummaryTable -Document $Document `
    -Title $Title `
    -Data $summary `
    -TableStyleName $TableStyleName `
    -InsertRange $InsertRange `
    -HeaderFontColor $HeaderFontColor

  # Top 10 largest mailboxes
  if ($currentRange) { $currentRange = $currentRange.Duplicate() }
  else {
    $currentRange = $Document.Range()
    $currentRange.Collapse(0) | Out-Null
  }

  $mailboxesWithSize = foreach ($mbx in $activeMailboxes) {
    [int64]$sizeVal = 0
    if (-not [int64]::TryParse([string]$mbx.'Storage Used (Byte)', [ref]$sizeVal)) { $sizeVal = 0 }

    [pscustomobject]@{
      DisplayName  = $mbx.'Display Name'
      UPN          = $mbx.'User Principal Name'
      SizeBytes    = $sizeVal
      SizeFormatted = Format-BytesHumanReadable -Bytes $sizeVal
      ItemCount    = $mbx.'Item Count'
      LastActivity = $mbx.'Last Activity Date'
    }
  }

  $top10 = $mailboxesWithSize | Sort-Object SizeBytes -Descending | Select-Object -First 10

  if ($top10.Count -gt 0) {
    $titlePara = $currentRange.Paragraphs.Add()
    $titlePara.Range.Text = "Top 10 Largest Mailboxes"
    $titlePara.Range.Style = "Caption"
    $titlePara.Range.InsertParagraphAfter() | Out-Null

    $afterHeading = $titlePara.Range.Duplicate()
    $afterHeading.Collapse(0) | Out-Null

    $rows = $top10.Count + 1
    $cols = 5

    $table = $Document.Tables.Add($afterHeading, $rows, $cols)
    $table.Range.Style = "Normal"

    $styleObj = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
    if ($styleObj) { $table.Style = $styleObj }

    $headers = @("Display Name", "UPN", "Size", "Item Count", "Last Activity")

    for ($c = 0; $c -lt $cols; $c++) {
      $cellRange = $table.Cell(1, $c + 1).Range
      $cellRange.Text = $headers[$c]
      $cellRange.Bold = $true
      Set-AdHeaderFontColor -Range $cellRange -HeaderFontColor $HeaderFontColor
    }

    $r = 2
    foreach ($row in $top10) {
      $table.Cell($r, 1).Range.Text = $row.DisplayName
      $table.Cell($r, 2).Range.Text = $row.UPN
      $table.Cell($r, 3).Range.Text = $row.SizeFormatted
      $table.Cell($r, 4).Range.Text = $row.ItemCount
      $table.Cell($r, 5).Range.Text = $row.LastActivity
      $r++
    }

    $table.Range.InsertParagraphAfter() | Out-Null

    $nextRange = $table.Range.Duplicate()
    $nextRange.Collapse(0) | Out-Null
    return $nextRange
  }

  return $currentRange
}
