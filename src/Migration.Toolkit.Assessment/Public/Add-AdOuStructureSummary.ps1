function Add-AdOuStructureSummary {
  <#
  .SYNOPSIS
  Creates an OU structure summary with depth analysis and distribution table.

  .DESCRIPTION
  Analyzes AD organizational unit CSV to calculate OU depth statistics, top-level OUs,
  leaf OUs, and produces a secondary table showing OU distribution by depth level.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to AD OU CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .EXAMPLE
  Add-AdOuStructureSummary -Document $doc -Title "OU Structure" -CsvPath "OUs.csv" -TableStyleName "Light Grid Accent 1"
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
    Write-Warning "OU CSV not found: $CsvPath"
    return $InsertRange
  }

  $ouData = Import-Csv $CsvPath
  if ($ouData.Count -eq 0) {
    Write-Warning "OU CSV '$CsvPath' is empty."
    return $InsertRange
  }

  # Ensure Depth column exists
  if (-not ($ouData[0].PSObject.Properties.Name -contains 'Depth')) {
    Write-Verbose "Depth column not found; deriving from DistinguishedName."
    foreach ($row in $ouData) {
      $ouCount = ([regex]::Matches($row.DistinguishedName, 'OU=')).Count
      $row | Add-Member -NotePropertyName 'Depth' -NotePropertyValue $ouCount -Force
    }
  }

  # Coerce Depth to int
  foreach ($row in $ouData) {
    try { $row.Depth = [int]$row.Depth } catch { $row.Depth = 0 }
  }

  $totalOUs = $ouData.Count
  $maxDepth = ($ouData.Depth | Measure-Object -Maximum).Maximum
  $avgDepthRaw = ($ouData.Depth | Measure-Object -Average).Average

  # Depth in CSV is 0-based; present as levels (1-based)
  $maxLevel = $maxDepth + 1
  $avgLevel = "{0:N1}" -f ($avgDepthRaw + 1)

  $topLevelCount = ($ouData | Where-Object { $_.Depth -eq 0 }).Count

  # Leaf OUs (not parents of any other OU)
  $allDns = $ouData.DistinguishedName
  $leafCount = 0
  foreach ($dn in $allDns) {
    $pattern = "*,{0}" -f $dn
    if (-not ($allDns -like $pattern)) { $leafCount++ }
  }

  # Depth distribution
  $depthGroups = $ouData | Group-Object Depth | Sort-Object Name

  $depthRows = foreach ($g in $depthGroups) {
    $level = [int]$g.Name + 1
    [pscustomobject]@{
      Level = $level
      OUs   = $g.Count
    }
  }

  # Summary table
  $summary = [ordered]@{
    "Total Organizational Units" = $totalOUs
    "Maximum OU Depth (levels)"  = $maxLevel
    "Average OU Depth (levels)"  = $avgLevel
    "Top-Level OUs (Level 1)"    = $topLevelCount
    "Leaf OUs (no child OUs)"    = $leafCount
  }

  $currentRange = Add-AdSimpleSummaryTable -Document $Document `
    -Title $Title `
    -Data $summary `
    -TableStyleName $TableStyleName `
    -InsertRange $InsertRange `
    -HeaderFontColor $HeaderFontColor

  # Depth distribution table
  if ($currentRange) { $currentRange = $currentRange.Duplicate() }
  else {
    $currentRange = $Document.Range()
    $currentRange.Collapse(0) | Out-Null
  }

  $hRange2 = $currentRange.Duplicate()
  $para2 = $hRange2.Paragraphs.Add()
  $para2.Range.Text = "$Title - Depth Distribution"
  $para2.Range.Style = "Caption"
  $para2.Range.InsertParagraphAfter() | Out-Null

  $afterHeading2 = $para2.Range.Duplicate()
  $afterHeading2.Collapse(0) | Out-Null

  $rows = $depthRows.Count + 1
  $cols = 2

  $table2 = $Document.Tables.Add($afterHeading2, $rows, $cols)
  $table2.Range.Style = "Normal"

  $styleObj = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
  if ($styleObj) { $table2.Style = $styleObj }

  # Header row
  $cell = $table2.Cell(1, 1).Range
  $cell.Text = "OU Depth Level"
  $cell.Bold = $true
  Set-AdHeaderFontColor -Range $cell -HeaderFontColor $HeaderFontColor

  $cell = $table2.Cell(1, 2).Range
  $cell.Text = "OUs"
  $cell.Bold = $true
  Set-AdHeaderFontColor -Range $cell -HeaderFontColor $HeaderFontColor

  # Data rows
  $r = 2
  foreach ($row in $depthRows) {
    $table2.Cell($r, 1).Range.Text = $row.Level
    $table2.Cell($r, 2).Range.Text = [string]$row.OUs
    $r++
  }

  $table2.Range.InsertParagraphAfter() | Out-Null

  $nextRange = $table2.Range.Duplicate()
  $nextRange.Collapse(0) | Out-Null
  return $nextRange
}
