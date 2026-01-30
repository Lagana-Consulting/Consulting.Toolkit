function Add-AdCountRowsSummary {
    <#
  .SYNOPSIS
  Creates a simple metric/value table showing the row count from a CSV file.

  .DESCRIPTION
  Reads a CSV file, counts the number of data rows (excluding header), and displays
  the count in a two-row table with a custom metric label. Useful for quick summary
  tables showing counts like "Total GPOs" or "Total Sites".

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table. Displayed above the table in Caption style.

  .PARAMETER CsvPath
  Path to the CSV file to count rows from.

  .PARAMETER MetricLabel
  The label for the metric (e.g., "Total GPOs", "Site Count"). Defaults to "Total Rows".

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .EXAMPLE
  Add-AdCountRowsSummary -Document $word.ActiveDocument `
    -Title "GPO Inventory" `
    -CsvPath "C:\data\GPOs.csv" `
    -MetricLabel "Total GPOs" `
    -TableStyleName "Grid Table 4 - Accent 1"

  Creates a table showing the count of rows in GPOs.csv with label "Total GPOs".

  .EXAMPLE
  $range = Get-AdBookmarkRange -Document $doc -BookmarkName "SiteCount"
  Add-AdCountRowsSummary -Document $doc -Title "Replication Sites" `
    -CsvPath "Sites.csv" -MetricLabel "Total Sites" -InsertRange $range

  Inserts site count at a specific bookmark location.

  .OUTPUTS
  Microsoft.Office.Interop.Word.Range
  Returns the range immediately after the inserted table for sequential insertions.
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [__ComObject]$Document,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$CsvPath,

        [string]$MetricLabel = "Total Rows",

        [string]$TableStyleName,

        [__ComObject]$InsertRange,

        $HeaderFontColor
    )

    # Count rows in CSV
    $rows = Import-Csv -Path $CsvPath -ErrorAction Stop
    $count = ($rows | Measure-Object).Count

    # Build simple metric/value pair
    $metrics = [ordered]@{
        $MetricLabel = $count
    }

    # Determine insert position
    if ($InsertRange) {
        $range = $InsertRange
    }
    else {
        $range = $Document.Content
        $range.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)
    }

    # Add caption paragraph
    $range.InsertAfter("`r`n")
    $range.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)
    $caption = $range.Paragraphs.Add($range)
    $caption.Range.Text = $Title
    $caption.Style = "Caption"
    $caption.Range.InsertParagraphAfter()

    # Create table (2 rows: header + 1 data row)
    $numRows = 2
    $numCols = 2
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)

    # Header row
    $table.Cell(1, 1).Range.Text = "Metric"
    $table.Cell(1, 2).Range.Text = "Value"
    $table.Rows.Item(1).HeadingFormat = -1

    # Data row
    $table.Cell(2, 1).Range.Text = $MetricLabel
    $table.Cell(2, 2).Range.Text = $count

    # Apply table style
    if ($TableStyleName) {
        $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
        if ($style) {
            $table.Style = $style
        }
    }

    $table.AutoFitBehavior([Microsoft.Office.Interop.Word.WdAutoFitBehavior]::wdAutoFitContent)

    # Apply header color
    if ($HeaderFontColor) {
        Set-AdHeaderFontColor -Table $table -Color $HeaderFontColor
    }

    # Return next insertion point
    $nextRange = $Document.Range($table.Range.End, $table.Range.End)
    return $nextRange
}
