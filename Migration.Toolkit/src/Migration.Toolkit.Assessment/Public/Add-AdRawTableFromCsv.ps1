function Add-AdRawTableFromCsv {
    <#
  .SYNOPSIS
  Creates a raw table from CSV data with optional column filtering and ordering.

  .DESCRIPTION
  Reads a CSV file and inserts all rows as a table in Word. Supports column
  selection, renaming, and ordering via the Columns parameter.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to CSV file.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER Columns
  Optional ordered hashtable mapping display names to CSV column names,
  or array of column names to include (preserves order).

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .EXAMPLE
  $cols = [ordered]@{ "User Name" = "DisplayName"; "Email" = "UserPrincipalName" }
  Add-AdRawTableFromCsv -Document $doc -Title "Users" -CsvPath "users.csv" -Columns $cols -TableStyleName "Light Grid Accent 1"
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $CsvPath,
        [Parameter(Mandatory)][string] $TableStyleName,
        $Columns = $null,
        $InsertRange = $null,
        [string] $HeaderFontColor
    )

    if (-not (Test-Path $CsvPath)) {
        Write-Warning "CSV not found: $CsvPath"
        return $InsertRange
    }

    $data = Import-Csv $CsvPath
    if ($data.Count -eq 0) {
        Write-Warning "CSV '$CsvPath' is empty."
        return $InsertRange
    }

    $availableCols = $data[0].PSObject.Properties.Name
    $headerMap = [ordered]@{}

    # Normalize Columns from JSON/PowerShell object
    if ($Columns -is [System.Management.Automation.PSCustomObject]) {
        $tmp = [ordered]@{}
        foreach ($p in $Columns.PSObject.Properties) { $tmp[$p.Name] = $p.Value }
        $Columns = $tmp
    }

    if ($Columns) {
        if ($Columns -is [System.Collections.IDictionary]) {
            foreach ($k in $Columns.Keys) {
                if ($availableCols -contains $Columns[$k]) { $headerMap[$k] = $Columns[$k] }
            }
        }
        elseif ($Columns -is [System.Collections.IEnumerable] -and $Columns -isnot [string]) {
            foreach ($c in $Columns) {
                if ($availableCols -contains $c) { $headerMap[$c] = $c }
            }
        }
    }

    # Fallback to all CSV columns
    if ($headerMap.Count -eq 0) {
        foreach ($col in $availableCols) { $headerMap[$col] = $col }
    }

    # Insert table
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

    $headers = @($headerMap.Keys)
    $rows = $data.Count + 1
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
    foreach ($row in $data) {
        for ($c = 0; $c -lt $cols; $c++) {
            $sourceCol = $headerMap[$headers[$c]]
            $table.Cell($r, $c + 1).Range.Text = [string]$row.$sourceCol
        }
        $r++
    }

    $table.Range.InsertParagraphAfter() | Out-Null

    $nextRange = $table.Range.Duplicate()
    $nextRange.Collapse(0) | Out-Null
    return $nextRange
}
