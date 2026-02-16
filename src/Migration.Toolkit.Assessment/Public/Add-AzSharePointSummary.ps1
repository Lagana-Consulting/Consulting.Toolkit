function Add-AzSharePointSummary {
    <#
  .SYNOPSIS
  Creates a SharePoint site summary table with primary metrics and top 10 largest sites.

  .DESCRIPTION
  Analyzes SharePoint site CSV data to generate:
  1. Primary summary table with total sites, storage, file counts, and activity metrics
  2. Secondary "Top 10 Largest SharePoint Sites" table with site URLs and storage details

  Expects CSV columns like: SiteUrl, StorageUsedGB, StorageQuotaGB, FileCount, LastActivityDate

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the primary summary table.

  .PARAMETER CsvPath
  Path to the CSV file containing SharePoint site data.

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .PARAMETER ActivityDays
  Number of days to consider for "active" classification. Defaults to 90.

  .EXAMPLE
  Add-AdSharePointSummary -Document $word.ActiveDocument `
    -Title "SharePoint Online Summary" `
    -CsvPath "C:\data\SharePoint_Sites.csv" `
    -TableStyleName "Grid Table 4 - Accent 1" `
    -ActivityDays 90

  Creates SharePoint summary with 90-day activity threshold.

  .OUTPUTS
  Microsoft.Office.Interop.Word.Range
  Returns the range immediately after the last inserted table for sequential insertions.
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

        [int]$ActivityDays = 90
    )

    # Import SharePoint data
    $sites = Import-Csv -Path $CsvPath -ErrorAction Stop
    if (-not $sites -or $sites.Count -eq 0) {
        Write-Warning "CSV file $CsvPath is empty or has no data rows."
        return $InsertRange
    }

    # Helper: Parse dates safely
    function Get-SafeDate($value) {
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        try {
            return [datetime]$value
        }
        catch {
            return $null
        }
    }

    # Helper: Sum column values as int64
    function Sum-ColumnAsInt64($data, $columnName) {
        $total = 0
        foreach ($row in $data) {
            $val = $row.$columnName
            if ($null -ne $val -and $val -ne '') {
                try {
                    $total += [int64]$val
                }
                catch {
                    # Ignore non-numeric values
                }
            }
        }
        return $total
    }

    # Helper: Format bytes
    function Format-BytesHumanReadable([int64]$bytes) {
        if ($bytes -ge 1TB) { return "{0:N2} TB" -f ($bytes / 1TB) }
        if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
        if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
        if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
        return "$bytes bytes"
    }

    # Calculate metrics
    $totalSites = $sites.Count
    $cutoffDate = (Get-Date).AddDays(-$ActivityDays)

    # Storage metrics (assume GB columns)
    $totalStorageGB = Sum-ColumnAsInt64 -data $sites -columnName 'StorageUsedGB'
    $totalQuotaGB = Sum-ColumnAsInt64 -data $sites -columnName 'StorageQuotaGB'

    # File count
    $totalFiles = Sum-ColumnAsInt64 -data $sites -columnName 'FileCount'

    # Activity analysis
    $activeSites = 0
    $inactiveSites = 0
    foreach ($site in $sites) {
        $lastActivityStr = $site.LastActivityDate
        $lastActivity = Get-SafeDate $lastActivityStr
        if ($lastActivity -and $lastActivity -ge $cutoffDate) {
            $activeSites++
        }
        else {
            $inactiveSites++
        }
    }

    # Find largest sites (top 10 by StorageUsedGB)
    $top10 = $sites | Where-Object { $_.StorageUsedGB -match '^\d+' } |
    Sort-Object { [int64]$_.StorageUsedGB } -Descending |
    Select-Object -First 10

    # Build primary summary metrics
    $metrics = [ordered]@{
        "Total SharePoint Sites"                 = $totalSites
        "Total Storage Used (GB)"                = "{0:N2}" -f $totalStorageGB
        "Total Quota Allocated (GB)"             = "{0:N2}" -f $totalQuotaGB
        "Total Files"                            = $totalFiles
        "Active Sites (Last $ActivityDays Days)" = $activeSites
        "Inactive Sites"                         = $inactiveSites
    }

    # Determine insert position
    if ($InsertRange) {
        $range = $InsertRange
    }
    else {
        $range = $Document.Content
        $range.Collapse(1)
    }

    # ========== PRIMARY SUMMARY TABLE ==========
    $range.InsertAfter("`r`n")
    $range.Collapse(1)
    $caption = $range.Paragraphs.Add($range)
    $caption.Range.Text = $Title
    $caption.Style = "Caption"
    $caption.Range.InsertParagraphAfter()

    $numRows = $metrics.Count + 1
    $numCols = 2
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)

    # Header
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

    if ($TableStyleName) {
        $style = Get-AdWordTableStyle -Document $Document -StyleName $TableStyleName
        if ($style) { $table.Style = $style }
    }

    $table.AutoFitBehavior(1)

    if ($HeaderFontColor) {
        Set-AdHeaderFontColor -Table $table -Color $HeaderFontColor
    }

    # ========== TOP 10 LARGEST SITES TABLE ==========
    if ($top10.Count -gt 0) {
        $nextRange = $Document.Range($table.Range.End, $table.Range.End)
        $nextRange.InsertAfter("`r`n")
        $nextRange.Collapse(1)

        $caption2 = $nextRange.Paragraphs.Add($nextRange)
        $caption2.Range.Text = "Top 10 Largest SharePoint Sites"
        $caption2.Style = "Caption"
        $caption2.Range.InsertParagraphAfter()

        $numRows2 = $top10.Count + 1
        $numCols2 = 5
        $tableRange2 = $caption2.Range.Next()
        $tableRange2.Collapse(1)
        $table2 = $Document.Tables.Add($tableRange2, $numRows2, $numCols2)

        # Header
        $table2.Cell(1, 1).Range.Text = "Site URL"
        $table2.Cell(1, 2).Range.Text = "Storage Used (GB)"
        $table2.Cell(1, 3).Range.Text = "Quota (GB)"
        $table2.Cell(1, 4).Range.Text = "File Count"
        $table2.Cell(1, 5).Range.Text = "Last Activity"
        $table2.Rows.Item(1).HeadingFormat = -1

        # Data rows
        $rowIndex2 = 2
        foreach ($site in $top10) {
            $table2.Cell($rowIndex2, 1).Range.Text = if ($site.SiteUrl) { $site.SiteUrl } else { "" }
            $table2.Cell($rowIndex2, 2).Range.Text = if ($site.StorageUsedGB) { $site.StorageUsedGB } else { "0" }
            $table2.Cell($rowIndex2, 3).Range.Text = if ($site.StorageQuotaGB) { $site.StorageQuotaGB } else { "" }
            $table2.Cell($rowIndex2, 4).Range.Text = if ($site.FileCount) { $site.FileCount } else { "0" }
            $table2.Cell($rowIndex2, 5).Range.Text = if ($site.LastActivityDate) { $site.LastActivityDate } else { "" }
            $rowIndex2++
        }

        if ($TableStyleName) {
            $style2 = Get-AdWordTableStyle -Document $Document -StyleName $TableStyleName
            if ($style2) { $table2.Style = $style2 }
        }

        $table2.AutoFitBehavior(1)

        if ($HeaderFontColor) {
            Set-AdHeaderFontColor -Table $table2 -Color $HeaderFontColor
        }

        $nextRange = $Document.Range($table2.Range.End, $table2.Range.End)
        return $nextRange
    }

    # Return next insertion point after primary table
    $nextRange = $Document.Range($table.Range.End, $table.Range.End)
    return $nextRange
}
