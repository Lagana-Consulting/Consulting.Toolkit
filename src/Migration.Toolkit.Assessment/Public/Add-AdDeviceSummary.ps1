function Add-AdDeviceSummary {
    <#
  .SYNOPSIS
  Creates an AD device summary table combining workstation and server metrics.

  .DESCRIPTION
  Analyzes AD workstation and server CSV exports to produce a combined summary
  showing enabled/disabled counts, activity windows (30/90/180+ days), and legacy OS counts.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER WorkstationsCsvPath
  Path to AD workstations CSV export.

  .PARAMETER ServersCsvPath
  Path to AD servers CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .EXAMPLE
  Add-AdDeviceSummary -Document $doc -Title "AD Device Summary" -WorkstationsCsvPath "workstations.csv" -ServersCsvPath "servers.csv" -TableStyleName "Light Grid Accent 1"
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $WorkstationsCsvPath,
        [Parameter(Mandatory)][string] $ServersCsvPath,
        [Parameter(Mandatory)][string] $TableStyleName,
        $InsertRange = $null,
        [string] $HeaderFontColor
    )

    # Import CSVs
    $workstations = if (Test-Path $WorkstationsCsvPath) {
        Import-Csv $WorkstationsCsvPath
    }
    else {
        Write-Warning "Workstations CSV not found: $WorkstationsCsvPath"
        @()
    }

    $servers = if (Test-Path $ServersCsvPath) {
        Import-Csv $ServersCsvPath
    }
    else {
        Write-Warning "Servers CSV not found: $ServersCsvPath"
        @()
    }

    if ($workstations.Count -eq 0 -and $servers.Count -eq 0) {
        Write-Warning "No device data found."
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

    # Helper to build metrics
    function Get-DeviceMetrics {
        param([array]$devices, [string]$totalLabel)

        $enabled = ($devices | Where-Object { $_.Enabled -eq "True" }).Count
        $disabled = ($devices | Where-Object { $_.Enabled -eq "False" }).Count

        $active30 = ($devices | Where-Object {
                $d = Get-LastLogonDays $_
                $null -ne $d -and $d -le 30
            }).Count

        $inactive31to90 = ($devices | Where-Object {
                $d = Get-LastLogonDays $_
                $null -ne $d -and $d -gt 30 -and $d -le 90
            }).Count

        $inactive91to180 = ($devices | Where-Object {
                $d = Get-LastLogonDays $_
                $null -ne $d -and $d -gt 90 -and $d -le 180
            }).Count

        $inactive180Plus = ($devices | Where-Object {
                $d = Get-LastLogonDays $_
                $null -ne $d -and $d -gt 180
            }).Count

        # Legacy OS devices
        $legacy = ($devices | Where-Object {
                $os = [string]$_.OperatingSystem
                $os -match "(Windows XP|Windows 7|Windows 8\.1|Server 2003|Server 2008)"
            }).Count

        return [ordered]@{
            $totalLabel              = $devices.Count
            "Enabled"                = $enabled
            "Disabled"               = $disabled
            "Active (≤30 days)"      = $active30
            "Inactive (31-90 days)"  = $inactive31to90
            "Inactive (91-180 days)" = $inactive91to180
            "Inactive (>180 days)"   = $inactive180Plus
            "Legacy OS Devices"      = $legacy
        }
    }

    $serverMetrics = Get-DeviceMetrics -devices $servers -totalLabel "Servers"
    $workstationMetrics = Get-DeviceMetrics -devices $workstations -totalLabel "Workstations"

    # Insert combined table
    if ($InsertRange) {
        $currentRange = $InsertRange.Duplicate()
    }
    else {
        $currentRange = $Document.Range()
        $currentRange.Collapse(0) | Out-Null
    }

    # Section heading
    $hRange = $currentRange.Duplicate()
    $para = $hRange.Paragraphs.Add()
    $para.Range.Text = $Title
    $para.Range.Style = "Caption"
    $para.Range.InsertParagraphAfter() | Out-Null

    $afterHeadingRange = $para.Range.Duplicate()
    $afterHeadingRange.Collapse(0) | Out-Null

    $serverCountRows = $serverMetrics.Count
    $workstationCountRows = $workstationMetrics.Count

    $rows = 1 + 1 + $serverCountRows + 1 + 1 + $workstationCountRows
    $cols = 2

    $table = $Document.Tables.Add($afterHeadingRange, $rows, $cols)
    $table.Range.Style = "Normal"

    $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
    if ($style) { $table.Style = $style }

    # Header row
    $headerMetricCell = $table.Cell(1, 1).Range
    $headerMetricCell.Text = "Metric"
    $headerMetricCell.Bold = $true
    Set-AdHeaderFontColor -Range $headerMetricCell -HeaderFontColor $HeaderFontColor

    $headerValueCell = $table.Cell(1, 2).Range
    $headerValueCell.Text = "Value"
    $headerValueCell.Bold = $true
    Set-AdHeaderFontColor -Range $headerValueCell -HeaderFontColor $HeaderFontColor

    $currentRow = 2

    # Servers section label (merged)
    $serversLabelCell = $table.Cell($currentRow, 1)
    $serversLabelCell.Range.Text = "Servers"
    $serversLabelCell.Range.Bold = $true
    $serversLabelCell.Range.ParagraphFormat.Alignment = 1  # center
    $serversLabelCell.Merge($table.Cell($currentRow, 2)) | Out-Null
    $currentRow++

    # Server metrics
    foreach ($key in $serverMetrics.Keys) {
        $table.Cell($currentRow, 1).Range.Text = $key
        $table.Cell($currentRow, 2).Range.Text = [string]$serverMetrics[$key]
        $currentRow++
    }

    # Blank separator
    $table.Cell($currentRow, 1).Range.Text = ""
    $table.Cell($currentRow, 2).Range.Text = ""
    $currentRow++

    # Workstations section label (merged)
    $wkLabelCell = $table.Cell($currentRow, 1)
    $wkLabelCell.Range.Text = "Workstations"
    $wkLabelCell.Range.Bold = $true
    $wkLabelCell.Range.ParagraphFormat.Alignment = 1
    $wkLabelCell.Merge($table.Cell($currentRow, 2)) | Out-Null
    $currentRow++

    # Workstation metrics
    foreach ($key in $workstationMetrics.Keys) {
        $table.Cell($currentRow, 1).Range.Text = $key
        $table.Cell($currentRow, 2).Range.Text = [string]$workstationMetrics[$key]
        $currentRow++
    }

    $table.Range.InsertParagraphAfter() | Out-Null

    $nextRange = $table.Range.Duplicate()
    $nextRange.Collapse(0) | Out-Null
    return $nextRange
}
