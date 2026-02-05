function Add-AdSingleRowSummaryFromCsv {
    <#
  .SYNOPSIS
  Extracts the first row from a CSV and renders it as a metric/value summary table.

  .DESCRIPTION
  Reads a CSV file containing a single row (or takes the first row if multiple exist),
  then converts column headers to metrics and cell values to values. Useful for domain
  summary CSVs where the first row contains aggregate statistics.

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table. Displayed above the table in Caption style.

  .PARAMETER CsvPath
  Path to the CSV file containing the data. First row will be extracted.

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .PARAMETER Columns
  Optional ordered hashtable or array to filter/rename columns.
  - OrderedHashtable: @{ "OldName" = "NewName" }
  - Array: @("Col1", "Col2") to filter columns in order
  If omitted, all columns are included in their natural order.

  .EXAMPLE
  Add-AdSingleRowSummaryFromCsv -Document $word.ActiveDocument `
    -Title "Forest Summary" `
    -CsvPath "C:\data\Forest_Summary.csv" `
    -TableStyleName "Grid Table 4 - Accent 1"

  Extracts the first row from Forest_Summary.csv and displays all columns as metrics.

  .EXAMPLE
  $range = Get-AdBookmarkRange -Document $doc -BookmarkName "ForestMetrics"
  Add-AdSingleRowSummaryFromCsv -Document $doc -Title "Forest Details" `
    -CsvPath "Forest.csv" -InsertRange $range `
    -Columns @{ "ForestFunctionalLevel" = "Functional Level"; "DomainCount" = "Total Domains" }

  Inserts at bookmark with column renaming.

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

        [string]$TableStyleName,

        [__ComObject]$InsertRange,

        $HeaderFontColor,

        [object]$Columns
    )

    # Import CSV (take first row only)
    $rawRow = Import-Csv -Path $CsvPath -ErrorAction Stop | Select-Object -First 1
    if (-not $rawRow) {
        Write-Warning "CSV file $CsvPath is empty or has no data rows."
        return $InsertRange
    }

    # Normalize columns
    if ($null -eq $Columns) {
        # Use all columns in their natural order
        $columnMap = [ordered]@{}
        $rawRow.PSObject.Properties | ForEach-Object {
            $columnMap[$_.Name] = $_.Name
        }
    }
    elseif ($Columns -is [System.Collections.Specialized.OrderedDictionary]) {
        $columnMap = $Columns
    }
    elseif ($Columns -is [array]) {
        $columnMap = [ordered]@{}
        foreach ($colName in $Columns) {
            $columnMap[$colName] = $colName
        }
    }
    else {
        # Convert PSCustomObject to ordered hashtable
        $columnMap = [ordered]@{}
        $Columns.PSObject.Properties | ForEach-Object {
            $columnMap[$_.Name] = $_.Value
        }
    }

    # Build metric/value pairs
    $metrics = [ordered]@{}
    foreach ($oldName in $columnMap.Keys) {
        $newName = $columnMap[$oldName]
        $value = $rawRow.$oldName
        if ($null -eq $value) { $value = "" }
        $metrics[$newName] = $value
    }

    # Determine insert position
    if ($InsertRange) {
        $range = $InsertRange
    }
    else {
        $range = $Document.Content
        $range.Collapse(1)
    }

    # Add caption paragraph
    $range.InsertAfter("`r`n")
    $range.Collapse(1)
    $caption = $range.Paragraphs.Add($range)
    $caption.Range.Text = $Title
    $caption.Style = "Caption"
    $caption.Range.InsertParagraphAfter()

    # Create table
    $numRows = $metrics.Count + 1  # +1 for header
    $numCols = 2
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)

    # Header row
    $table.Cell(1, 1).Range.Text = "Metric"
    $table.Cell(1, 2).Range.Text = "Value"
    $table.Rows.Item(1).HeadingFormat = -1

    # Data rows
    $rowIndex = 2
    foreach ($key in $metrics.Keys) {
        $table.Cell($rowIndex, 1).Range.Text = $key
        $table.Cell($rowIndex, 2).Range.Text = $metrics[$key]
        $rowIndex++
    }

    # Apply table style
    if ($TableStyleName) {
        $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
        if ($style) {
            $table.Style = $style
        }
    }

    $table.AutoFitBehavior(1)

    # Apply header color
    if ($HeaderFontColor) {
        Set-AdHeaderFontColor -Table $table -Color $HeaderFontColor
    }

    # Return next insertion point
    $nextRange = $Document.Range($table.Range.End, $table.Range.End)
    return $nextRange
}
