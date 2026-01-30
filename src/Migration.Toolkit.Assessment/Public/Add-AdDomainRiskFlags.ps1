function Add-AdDomainRiskFlags {
    <#
  .SYNOPSIS
  Creates a domain-level risk flags table showing individual objects with risk flags.

  .DESCRIPTION
  Generates a table from the domain risk flags CSV showing all objects that have
  migration risk flags (e.g., stale accounts, disabled accounts, legacy OS, etc.).

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the domain risk flags CSV file (*__MigrationRiskFlags__Domain-*.csv).

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .PARAMETER Columns
  Optional hashtable mapping CSV column names to display names.
  Default: @{
    "ObjectClass" = "Object Type"
    "DomainFqdn" = "Domain"
    "SamAccountName" = "Account Name"
    "Flags" = "Risk Flags"
  }

  .EXAMPLE
  Add-AdDomainRiskFlags -Document $word.ActiveDocument `
    -Title "Domain Risk Flags" `
    -CsvPath "C:\data\AD__Domain__Analysis__MigrationRiskFlags__Domain-contoso.com.csv" `
    -TableStyleName "Grid Table 4 - Accent 1"

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

        [hashtable]$Columns
    )

    # Default column mapping
    if (-not $Columns) {
        $Columns = @{
            "ObjectClass" = "Object Type"
            "DomainFqdn" = "Domain"
            "SamAccountName" = "Account Name"
            "Flags" = "Risk Flags"
        }
    }

    # Import risk flags data
    $riskData = Import-Csv -Path $CsvPath -ErrorAction Stop
    if (-not $riskData -or $riskData.Count -eq 0) {
        Write-Warning "CSV file $CsvPath is empty or has no data rows."
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
    $numRows = $riskData.Count + 1  # +1 for header
    $numCols = $Columns.Count
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)

    # Set table content style to Normal before applying table style
    $table.Range.Style = "Normal"

    # Header row
    $colIndex = 1
    foreach ($csvCol in $Columns.Keys) {
        $displayName = $Columns[$csvCol]
        $table.Cell(1, $colIndex).Range.Text = $displayName
        $colIndex++
    }
    $table.Rows.Item(1).HeadingFormat = -1

    # Data rows
    $rowIndex = 2
    foreach ($row in $riskData) {
        $colIndex = 1
        foreach ($csvCol in $Columns.Keys) {
            $value = $row.$csvCol
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
