function Add-AdDomainInformation {
    <#
  .SYNOPSIS
  Creates a domain information table with domain-level metrics and configuration.

  .DESCRIPTION
  Generates a metric/value table showing domain information including:
  - Domain Name
  - Active Workstations
  - AD Recycle Bin Enabled
  - Disabled Users
  - Discovery Date
  - Domain Controller Count
  - Empty Groups
  - Enabled Users
  - Site Count
  - Stale Users
  - Subnet Count
  - Total Contacts
  - Total GPOs
  - Total Groups
  - Total OUs
  - Total Printers
  - Total Servers
  - Total Users
  - Total Workstations
  - Trust Count

  Expects CSV file with columns matching the metrics above.

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the CSV file containing domain information data. First row will be extracted.

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .EXAMPLE
  Add-AdDomainInformation -Document $word.ActiveDocument `
    -Title "Domain Information Summary" `
    -CsvPath "C:\data\Domain_Summary.csv" `
    -TableStyleName "Grid Table 4 - Accent 1"

  Creates domain information table from CSV data.

  .EXAMPLE
  $range = Get-AdBookmarkRange -Document $doc -BookmarkName "DomainMetadata"
  Add-AdDomainInformation -Document $doc -Title "Domain Details" `
    -CsvPath "Domain.csv" -InsertRange $range -HeaderFontColor "#003087"

  Inserts domain information at a specific bookmark location with custom color.

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

        $HeaderFontColor
    )

    # Import CSV (take first row only)
    $rawRow = Import-Csv -Path $CsvPath -ErrorAction Stop | Select-Object -First 1
    if (-not $rawRow) {
        Write-Warning "CSV file $CsvPath is empty or has no data rows."
        return $InsertRange
    }

    # Define domain metrics in display order (map actual CSV columns)
    # CSV columns: DomainFqdn, DomainDn, NetBIOSName, DomainMode, PdcEmulator, RidMaster, InfrastructureMaster, ServerUsed
    $domainColumns = [ordered]@{
        "DomainFqdn"           = "Domain FQDN"
        "NetBIOSName"          = "NetBIOS Name"
        "DomainMode"           = "Domain Mode"
        "PdcEmulator"          = "PDC Emulator"
        "RidMaster"            = "RID Master"
        "InfrastructureMaster" = "Infrastructure Master"
    }

    # Build metric/value pairs from CSV row
    $metrics = [ordered]@{}
    foreach ($oldName in $domainColumns.Keys) {
        $newName = $domainColumns[$oldName]
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
    
    # Set table content style to Normal before applying table style
    $table.Range.Style = "Normal"


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




