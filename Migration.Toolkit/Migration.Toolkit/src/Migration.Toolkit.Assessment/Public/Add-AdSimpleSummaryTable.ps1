function Add-AdSimpleSummaryTable {
    <#
  .SYNOPSIS
  Creates a simple metric/value summary table in a Word document.

  .DESCRIPTION
  Inserts a two-column table (Metric | Value) with an optional caption.
  Commonly used for high-level summaries with key metrics.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER Data
  Ordered hashtable or dictionary of metric names (keys) and values.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted. If null, inserts at document end.

  .PARAMETER HeaderFontColor
  Optional color for header row (hex like #003087 or OLE color integer).

  .EXAMPLE
  $summary = [ordered]@{ "Total Users" = 1500; "Enabled" = 1200 }
  Add-AdSimpleSummaryTable -Document $doc -Title "User Summary" -Data $summary -TableStyleName "Light Grid Accent 1"
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)] $Data,
        [Parameter(Mandatory)][string] $TableStyleName,
        $InsertRange = $null,
        [string] $HeaderFontColor
    )

    if ($InsertRange) {
        $currentRange = $InsertRange.Duplicate()
    }
    else {
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

    # Ensure ordered dictionary
    if ($Data -isnot [System.Collections.Specialized.OrderedDictionary]) {
        $ordered = [ordered]@{}
        foreach ($k in $Data.Keys) { $ordered[$k] = $Data[$k] }
        $Data = $ordered
    }

    # Table
    $rows = $Data.Keys.Count + 1
    $cols = 2
    $table = $Document.Tables.Add($afterHeadingRange, $rows, $cols)
    $table.Range.Style = "Normal"

    $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
    if ($style) { $table.Style = $style }

    # Header row
    $cell = $table.Cell(1, 1)
    $cell.Range.Text = "Metric"
    $cell.Range.Bold = $true
    Set-AdHeaderFontColor -Range $cell.Range -HeaderFontColor $HeaderFontColor

    $cell = $table.Cell(1, 2)
    $cell.Range.Text = "Value"
    $cell.Range.Bold = $true
    Set-AdHeaderFontColor -Range $cell.Range -HeaderFontColor $HeaderFontColor

    # Data rows
    $r = 2
    foreach ($k in $Data.Keys) {
        $table.Cell($r, 1).Range.Text = $k
        $table.Cell($r, 2).Range.Text = [string]$Data[$k]
        $r++
    }

    $table.Range.InsertParagraphAfter() | Out-Null

    $nextRange = $table.Range.Duplicate()
    $nextRange.Collapse(0) | Out-Null
    return $nextRange
}
