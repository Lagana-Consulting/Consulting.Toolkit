function Add-AdTrustInformation {
    <#
  .SYNOPSIS
  Creates a trust relationship table showing forest and domain trusts.

  .DESCRIPTION
  Generates a table displaying trust relationship information including:
  - Trust Name
  - Direction (Inbound, Outbound, Bidirectional)
  - Trust Type (External, Forest, Transitive, Shortcut)
  - Disallow Transivity (true/false)
  - Selective Authentication (true/false)
  - Forest Transitive (true/false)

  Expects CSV columns: Name, Direction, TrustType, DisallowTransivity,
  SelectiveAuthentication, ForestTransitive

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the CSV file containing trust relationship data.

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
  If omitted, uses default columns: Name, Direction, TrustType, DisallowTransivity,
  SelectiveAuthentication, ForestTransitive

  .EXAMPLE
  Add-AdTrustInformation -Document $word.ActiveDocument `
    -Title "Forest and Domain Trusts" `
    -CsvPath "C:\data\Forest_Trusts.csv" `
    -TableStyleName "Grid Table 4 - Accent 1"

  Creates trust information table with all default columns.

  .EXAMPLE
  $range = Get-AdBookmarkRange -Document $doc -BookmarkName "Trusts"
  Add-AdTrustInformation -Document $doc -Title "Trust Relationships" `
    -CsvPath "Trusts.csv" -InsertRange $range `
    -Columns @("Name", "Direction", "TrustType", "SelectiveAuthentication")

  Creates table with specific columns at a bookmark location.

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

    # Define default columns if not specified
    if ($null -eq $Columns) {
        $Columns = [ordered]@{
            "Name"                    = "Trust Name"
            "Direction"               = "Direction"
            "TrustType"               = "Trust Type"
            "DisallowTransivity"      = "Disallow Transitivity"
            "SelectiveAuthentication" = "Selective Authentication"
            "ForestTransitive"        = "Forest Transitive"
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
    $numRows = $data.Count + 1  # +1 for header
    $numCols = $validColumns.Count
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)
    
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
            $table.Cell($rowIndex, $colIndex).Range.Text = $value
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




