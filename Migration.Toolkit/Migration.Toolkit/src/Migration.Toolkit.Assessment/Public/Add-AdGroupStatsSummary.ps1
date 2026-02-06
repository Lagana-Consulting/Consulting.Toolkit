function Add-AdGroupStatsSummary {
    <#
  .SYNOPSIS
  Creates a group statistics summary table showing group counts by category and scope.

  .DESCRIPTION
  Generates a table displaying group statistics broken down by:
  - Group Category (Distribution, Security)
  - Group Scope (Domain Local, Global, Universal)
  - Count (number of groups in each category/scope combination)

  Expects CSV columns: GroupCategory, GroupScope, Count

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the CSV file containing group statistics data.

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
  If omitted, uses default columns: GroupCategory, GroupScope, Count

  .EXAMPLE
  Add-AdGroupStatsSummary -Document $word.ActiveDocument `
    -Title "Group Statistics by Category and Scope" `
    -CsvPath "C:\data\GroupStats.csv" `
    -TableStyleName "Grid Table 4 - Accent 1"

  Creates group statistics table with all default columns.

  .EXAMPLE
  $range = Get-AdBookmarkRange -Document $doc -BookmarkName "GroupStats"
  Add-AdGroupStatsSummary -Document $doc -Title "Group Breakdown" `
    -CsvPath "Groups.csv" -InsertRange $range -HeaderFontColor "#003087"

  Creates table at a bookmark location with custom header color.

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

    # Import CSV data
    $data = Import-Csv -Path $CsvPath -ErrorAction Stop
    if (-not $data -or $data.Count -eq 0) {
        Write-Warning "CSV file $CsvPath is empty or has no data rows."
        return $InsertRange
    }

    # If GroupCategory and GroupScope columns exist, pivot the data
    $firstRow = $data[0]
    $availableColumns = $firstRow.PSObject.Properties.Name

    if ($availableColumns -contains 'GroupCategory' -and $availableColumns -contains 'GroupScope') {
        # Pivot groups by category and scope
        $data = $data | Group-Object GroupCategory, GroupScope | ForEach-Object {
            $parts = $_.Name -split ', '
            [pscustomobject]@{
                GroupCategory = $parts[0]
                GroupScope    = $parts[1]
                Count         = $_.Count
            }
        } | Sort-Object GroupCategory, GroupScope
    }

    # Define default columns if not specified
    if ($null -eq $Columns) {
        $Columns = [ordered]@{
            "GroupCategory" = "Group Category"
            "GroupScope"    = "Group Scope"
            "Count"         = "Count"
        }
    }

    # Normalize columns to ordered hashtable
    if ($Columns -is [System.Collections.Specialized.OrderedDictionary]) {
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

    # Validate columns exist in CSV
    $firstRow = $data[0]
    $availableColumns = $firstRow.PSObject.Properties.Name
    $validColumns = [ordered]@{}
    foreach ($oldName in $columnMap.Keys) {
        if ($availableColumns -contains $oldName) {
            $validColumns[$oldName] = $columnMap[$oldName]
        }
        else {
            Write-Warning "Column '$oldName' not found in CSV, skipping."
        }
    }

    if ($validColumns.Count -eq 0) {
        Write-Warning "No valid columns found in CSV file."
        return $InsertRange
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
    # Ensure row and column counts are integers
    $numRows = @($data).Count + 1  # +1 for header
    $numCols = @($validColumns.Keys).Count

    # Validate counts are positive integers
    if ($numRows -lt 2 -or $numCols -lt 1) {
        Write-Warning "Invalid table dimensions: rows=$numRows, cols=$numCols"
        return $InsertRange
    }

    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, [int]$numRows, [int]$numCols)

    # Set table content style to Normal before applying table style
    $table.Range.Style = "Normal"


    # Header row
    $colIndex = 1
    foreach ($newName in $validColumns.Values) {
        $table.Cell(1, $colIndex).Range.Text = $newName
        $colIndex++
    }
    $table.Rows.Item(1).HeadingFormat = -1

    # Data rows
    $rowIndex = 2
    foreach ($row in $data) {
        $colIndex = 1
        foreach ($oldName in $validColumns.Keys) {
            $value = $row.$oldName
            if ($null -eq $value) { $value = "" }
            $table.Cell($rowIndex, $colIndex).Range.Text = [string]$value
            $colIndex++
        }
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




