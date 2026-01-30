function Add-AdDomainDiscoveryTable {
    <#
  .SYNOPSIS
  Creates a domain discovery table showing domain metadata and FSMO role holders.

  .DESCRIPTION
  Generates a table with domain/forest information including:
  - Domain/Forest Name
  - Functional Level
  - Domain Controllers count
  - FSMO role holders (PDC, RID, Infrastructure, Schema Master, Domain Naming Master)
  - Site information
  - Trust relationships

  Expects CSV columns like: DomainName, ForestName, FunctionalLevel, PDCEmulator,
  RIDMaster, InfrastructureMaster, SchemaMaster, DomainNamingMaster, etc.

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the CSV file containing domain discovery data.

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
  If omitted, uses default columns: DomainName, FunctionalLevel, PDCEmulator,
  RIDMaster, InfrastructureMaster, SchemaMaster, DomainNamingMaster

  .EXAMPLE
  Add-AdDomainDiscoveryTable -Document $word.ActiveDocument `
    -Title "Domain and Forest Information" `
    -CsvPath "C:\data\Domain_Summary.csv" `
    -TableStyleName "Grid Table 4 - Accent 1"

  Creates domain discovery table with default columns.

  .EXAMPLE
  $columns = [ordered]@{
    "DomainName" = "Domain"
    "FunctionalLevel" = "Functional Level"
    "PDCEmulator" = "PDC Emulator"
    "RIDMaster" = "RID Master"
  }
  Add-AdDomainDiscoveryTable -Document $doc -Title "Domain Metadata" `
    -CsvPath "Domain.csv" -Columns $columns

  Creates table with custom column selection and renaming.

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
            "DomainName"           = "Domain Name"
            "FunctionalLevel"      = "Functional Level"
            "PDCEmulator"          = "PDC Emulator"
            "RIDMaster"            = "RID Master"
            "InfrastructureMaster" = "Infrastructure Master"
            "SchemaMaster"         = "Schema Master"
            "DomainNamingMaster"   = "Domain Naming Master"
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
        $range.Collapse(1)  # wdCollapseEnd = 1
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
