function Add-AzM365GroupSummary {
    <#
  .SYNOPSIS
  Creates an M365 group summary table with activity and storage metrics.

  .DESCRIPTION
  Analyzes M365 group CSV data to calculate active/inactive groups, mailbox storage,
  SharePoint storage, and activity counts.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to M365 groups CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .EXAMPLE
  Add-AdM365GroupSummary -Document $doc -Title "M365 Group Summary" -CsvPath "M365_Groups.csv" -TableStyleName "Light Grid Accent 1"
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

    if (-not (Test-Path $CsvPath)) {
        Write-Warning "M365 Group CSV not found: $CsvPath"
        return $InsertRange
    }

    $groups = Import-Csv $CsvPath
    if ($groups.Count -eq 0) {
        Write-Warning "M365 Group CSV '$CsvPath' is empty."
        return $InsertRange
    }

    # Helper: sum column as int64
    function Sum-ColumnAsInt64 {
        param([array]$Rows, [string]$ColumnName)
        $sum = [int64]0
        foreach ($row in $Rows) {
            [int64]$val = 0
            if ([int64]::TryParse([string]$row.$ColumnName, [ref]$val)) { $sum += $val }
        }
        return $sum
    }

    # Helper: format bytes
    function Format-BytesHumanReadable {
        param([int64] $Bytes)
        if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
        elseif ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
        elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
        else { return "{0:N2} KB" -f ($Bytes / 1KB) }
    }

    # Basic counts
    $total = $groups.Count

    $now = Get-Date
    $active = ($groups | Where-Object {
            $_.'Last Activity Date' -and ((Get-Date $_.'Last Activity Date') -gt $now.AddDays(-90))
        }).Count

    $inactive = $total - $active
    $deleted = ($groups | Where-Object { $_.'Is Deleted' -eq "True" }).Count

    # Activity
    $mailActive = ($groups | Where-Object {
            [int]($_.'Exchange Received Email Count') -gt 0
        }).Count

    $fileActive = ($groups | Where-Object {
            [int]($_.'SharePoint Active File Count') -gt 0
        }).Count

    $noActivity = ($groups | Where-Object {
            [int]($_.'Exchange Received Email Count') -eq 0 -and
            [int]($_.'SharePoint Active File Count') -eq 0
        }).Count

    # Ownership
    $noOwners = ($groups | Where-Object {
            [string]::IsNullOrWhiteSpace($_.'Owner Principal Name')
        }).Count

    # Aggregated totals
    $totalExItems = Sum-ColumnAsInt64 -Rows $groups -ColumnName 'Exchange Mailbox Total Item Count'
    $totalExBytes = Sum-ColumnAsInt64 -Rows $groups -ColumnName 'Exchange Mailbox Storage Used (Byte)'

    $totalSpFiles = Sum-ColumnAsInt64 -Rows $groups -ColumnName 'SharePoint Total File Count'
    $totalSpBytes = Sum-ColumnAsInt64 -Rows $groups -ColumnName 'SharePoint Site Storage Used (Byte)'

    $totalExStorageFormatted = Format-BytesHumanReadable -Bytes $totalExBytes
    $totalSpStorageFormatted = Format-BytesHumanReadable -Bytes $totalSpBytes

    # Summary
    $summary = [ordered]@{
        "Total M365 Groups"                      = $total
        "Active Groups (≤ 90d)"                  = $active
        "Inactive Groups (> 90d)"                = $inactive
        "Deleted Groups"                         = $deleted
        "Groups Receiving Email"                 = $mailActive
        "Groups with Active Files"               = $fileActive
        "Groups with No Activity (Mail + Files)" = $noActivity
        "Groups with No Owners"                  = $noOwners
        "Exchange Mailbox Total Items"           = $totalExItems
        "Exchange Total Mailbox Storage Used"    = $totalExStorageFormatted
        "SharePoint Total File Count"            = $totalSpFiles
        "SharePoint Site Total Storage Used"     = $totalSpStorageFormatted
    }

    return Add-AdSimpleSummaryTable -Document $Document `
        -Title $Title `
        -Data $summary `
        -TableStyleName $TableStyleName `
        -InsertRange $InsertRange `
        -HeaderFontColor $HeaderFontColor
}
