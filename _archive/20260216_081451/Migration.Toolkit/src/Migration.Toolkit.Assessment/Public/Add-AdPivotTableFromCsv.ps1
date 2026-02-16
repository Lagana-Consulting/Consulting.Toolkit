function Add-AdPivotTableFromCsv {
  <#
  .SYNOPSIS
  Creates a pivot table from CSV data with grouping and aggregation.

  .DESCRIPTION
  Reads a CSV file, groups by specified columns, and aggregates a metric
  (count, distinct count, or sum). Useful for summarizing data by categories.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to CSV file.

  .PARAMETER GroupByColumns
  Array of column names to group by (like pivot rows).

  .PARAMETER MetricColumn
  Optional column to aggregate (e.g., "UserPrincipalName").

  .PARAMETER MetricAggregation
  Aggregation type: Count, DistinctCount, or Sum.

  .PARAMETER MetricLabel
  Header name for the metric column (e.g., "Count").

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .EXAMPLE
  Add-AdPivotTableFromCsv -Document $doc -Title "Users by Department" -CsvPath "users.csv" -GroupByColumns @("Department") -MetricLabel "Count" -TableStyleName "Light Grid Accent 1"
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] $Document,
    [Parameter(Mandatory)][string] $Title,
    [Parameter(Mandatory)][string] $CsvPath,
    [Parameter(Mandatory)][string[]] $GroupByColumns,
    [string] $MetricColumn = $null,
    [ValidateSet('Count', 'DistinctCount', 'Sum')]
    [string] $MetricAggregation = 'Count',
    [string] $MetricLabel = 'Count',
    [Parameter(Mandatory)][string] $TableStyleName,
    $InsertRange = $null,
    [string] $HeaderFontColor
  )

  if (-not (Test-Path $CsvPath)) {
    Write-Warning "Pivot CSV not found: $CsvPath"
    return $InsertRange
  }

  $data = Import-Csv $CsvPath
  if ($data.Count -eq 0) {
    Write-Warning "CSV '$CsvPath' is empty."
    return $InsertRange
  }

  # Validate group-by columns
  $availableCols = $data[0].PSObject.Properties.Name
  foreach ($g in $GroupByColumns) {
    if ($availableCols -notcontains $g) {
      Write-Warning "Group-by column '$g' not found in CSV."
      return $InsertRange
    }
  }

  # Build pivoted summary
  $grouped = $data | Group-Object -Property $GroupByColumns

  $pivotRows = foreach ($grp in $grouped) {
    $first = $grp.Group[0]

    $rowHash = [ordered]@{}
    foreach ($g in $GroupByColumns) {
      $rowHash[$g] = $first.$g
    }

    switch ($MetricAggregation) {
      'Count' {
        $value = $grp.Count
      }
      'DistinctCount' {
        if ($MetricColumn) {
          $value = ($grp.Group | Select-Object -ExpandProperty $MetricColumn -Unique).Count
        } else {
          $value = $grp.Count
        }
      }
      'Sum' {
        if ($MetricColumn) {
          $value = ($grp.Group | Measure-Object -Property $MetricColumn -Sum).Sum
        } else {
          $value = 0
        }
      }
    }

    $rowHash[$MetricLabel] = $value
    [pscustomobject]$rowHash
  }

  $pivotRows = @($pivotRows)

  if ($pivotRows.Count -eq 0) {
    Write-Warning "No pivot rows produced from '$CsvPath'."
    return $InsertRange
  }

  # Insert into Word
  if ($InsertRange) {
    $currentRange = $InsertRange.Duplicate()
  } else {
    $currentRange = $Document.Range()
    $currentRange.Collapse(0) | Out-Null
  }

  # Heading
  $hRange = $currentRange.Duplicate()
  $para = $hRange.Paragraphs.Add()
  $para.Range.Text = $Title
  $para.Range.Style = "Caption"
  $para.Range.InsertParagraphAfter() | Out-Null

  $afterHeadingRange = $para.Range.Duplicate()
  $afterHeadingRange.Collapse(0) | Out-Null

  # Columns: group-by + metric
  $headers = @($GroupByColumns + $MetricLabel)
  $rows = $pivotRows.Count + 1
  $cols = $headers.Count

  $table = $Document.Tables.Add($afterHeadingRange, $rows, $cols)
  $table.Range.Style = "Normal"

  $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
  if ($style) { $table.Style = $style }

  # Header row
  for ($c = 0; $c -lt $cols; $c++) {
    $displayName = [string]$headers[$c]
    $cellRange = $table.Cell(1, $c + 1).Range
    $cellRange.Text = $displayName
    $cellRange.Bold = $true
    Set-AdHeaderFontColor -Range $cellRange -HeaderFontColor $HeaderFontColor
  }

  # Data rows
  $r = 2
  foreach ($row in $pivotRows) {
    for ($c = 0; $c -lt $cols; $c++) {
      $colName = $headers[$c]
      $table.Cell($r, $c + 1).Range.Text = [string]$row.$colName
    }
    $r++
  }

  $table.Range.InsertParagraphAfter() | Out-Null

  $nextRange = $table.Range.Duplicate()
  $nextRange.Collapse(0) | Out-Null
  return $nextRange
}
