function Add-AdServerSummary {
    <#
  .SYNOPSIS
  Creates a server summary table showing device statistics.

  .DESCRIPTION
  Generates a table displaying server metrics including:
  - Total servers
  - Enabled/Disabled counts
  - Activity status (Active ≤30 days, Inactive ranges)
  - Legacy OS devices

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the servers CSV file.

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .EXAMPLE
  Add-AdServerSummary -Document $doc -Title "Server Summary" `
    -CsvPath "servers.csv" -TableStyleName "Grid Table 4 - Accent 1"
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $CsvPath,
        [Parameter(Mandatory)][string] $TableStyleName,
        $InsertRange = $null,
        [string] $HeaderFontColor
    )

    # Import CSV
    if (-not (Test-Path $CsvPath)) {
        Write-Warning "Servers CSV not found: $CsvPath"
        return $InsertRange
    }

    $devices = Import-Csv $CsvPath
    if (@($devices).Count -eq 0) {
        Write-Warning "No server data found."
        return $InsertRange
    }

    # Helper: safe LastLogonDays int
    function Get-LastLogonDays {
        param($row)
        try {
            $val = [int]$row.LastLogonDays
            return $val
        }
        catch {
            return $null
        }
    }

    # Calculate metrics
    $total = @($devices).Count

    $enabled = try {
        @($devices | Where-Object { $_.Enabled -eq "True" -or $_.Enabled -eq $true }).Count
    } catch { 0 }

    $disabled = try {
        @($devices | Where-Object { $_.Enabled -eq "False" -or $_.Enabled -eq $false }).Count
    } catch { 0 }

    $active30 = try {
        @($devices | Where-Object {
            $d = Get-LastLogonDays $_
            $null -ne $d -and $d -le 30
        }).Count
    } catch { 0 }

    $inactive31to90 = try {
        @($devices | Where-Object {
            $d = Get-LastLogonDays $_
            $null -ne $d -and $d -gt 30 -and $d -le 90
        }).Count
    } catch { 0 }

    $inactive91to180 = try {
        @($devices | Where-Object {
            $d = Get-LastLogonDays $_
            $null -ne $d -and $d -gt 90 -and $d -le 180
        }).Count
    } catch { 0 }

    $inactive180Plus = try {
        @($devices | Where-Object {
            $d = Get-LastLogonDays $_
            $null -ne $d -and $d -gt 180
        }).Count
    } catch { 0 }

    # Legacy OS devices
    $legacy = try {
        @($devices | Where-Object {
            $os = [string]$_.OperatingSystem
            $os -match "(Server 2003|Server 2008)"
        }).Count
    } catch { 0 }

    # Create metrics hashtable
    $metrics = [ordered]@{
        "Servers"                = $total
        "Legacy OS Devices (XP/7/2008/2008 R2)" = $legacy
        "Enabled Devices"        = $enabled
        "Inactive (>180 days)"   = $inactive180Plus
        "Inactive (91-180 days)" = $inactive91to180
        "Disabled Devices"       = $disabled
        "Inactive (31-90 days)"  = $inactive31to90
        "Active (LastLogon ≤ 30 days)" = $active30
    }

    # Insert table
    if ($InsertRange) {
        $currentRange = $InsertRange.Duplicate()
    }
    else {
        $currentRange = $Document.Range()
        $currentRange.Collapse(0) | Out-Null
    }

    # Caption
    $hRange = $currentRange.Duplicate()
    $para = $hRange.Paragraphs.Add()
    $para.Range.Text = $Title
    $para.Range.Style = "Caption"
    $para.Range.InsertParagraphAfter() | Out-Null

    $afterHeadingRange = $para.Range.Duplicate()
    $afterHeadingRange.Collapse(0) | Out-Null

    # Create table: 1 header + 8 metrics rows
    $rows = 9
    $cols = 2

    $table = $Document.Tables.Add($afterHeadingRange, $rows, $cols)
    $table.Range.Style = "Normal"

    $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
    if ($style) { $table.Style = $style }

    # Header row
    $table.Cell(1, 1).Range.Text = "Metric"
    $table.Cell(1, 1).Range.Bold = $true
    $table.Cell(1, 2).Range.Text = "Value"
    $table.Cell(1, 2).Range.Bold = $true
    $table.Rows.Item(1).HeadingFormat = -1

    if ($HeaderFontColor) {
        Set-AdHeaderFontColor -Table $table -Color $HeaderFontColor
    }

    # Data rows
    $currentRow = 2
    foreach ($key in $metrics.Keys) {
        $table.Cell($currentRow, 1).Range.Text = $key
        $table.Cell($currentRow, 2).Range.Text = [string]$metrics[$key]
        $currentRow++
    }

    $table.AutoFitBehavior(1)
    $table.Range.InsertParagraphAfter() | Out-Null

    $nextRange = $table.Range.Duplicate()
    $nextRange.Collapse(0) | Out-Null
    return $nextRange
}
