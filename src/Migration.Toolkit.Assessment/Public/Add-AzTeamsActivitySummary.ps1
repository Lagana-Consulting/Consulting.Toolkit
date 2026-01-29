function Add-AzTeamsActivitySummary {
    <#
  .SYNOPSIS
  Creates a Teams activity summary table with primary metrics and top 10 most active teams.

  .DESCRIPTION
  Analyzes Teams activity CSV data to generate:
  1. Primary summary table with total teams, active/inactive counts, channels, messages
  2. Secondary "Top 10 Most Active Teams" table with team names and activity metrics

  Expects CSV columns like: TeamName, ChannelCount, PostCount, LastActivityDate, MemberCount

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the primary summary table.

  .PARAMETER CsvPath
  Path to the CSV file containing Teams activity data.

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
  Add-AdTeamsActivitySummary -Document $word.ActiveDocument `
    -Title "Microsoft Teams Activity Summary" `
    -CsvPath "C:\data\Teams_Activity.csv" `
    -TableStyleName "Grid Table 4 - Accent 1" `
    -ActivityDays 90

  Creates Teams summary with 90-day activity threshold.

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

    # Import Teams data
    $teams = Import-Csv -Path $CsvPath -ErrorAction Stop
    if (-not $teams -or $teams.Count -eq 0) {
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

    # Calculate metrics
    $totalTeams = $teams.Count
    $cutoffDate = (Get-Date).AddDays(-$ActivityDays)

    # Activity analysis
    $activeTeams = 0
    $inactiveTeams = 0
    foreach ($team in $teams) {
        $lastActivityStr = $team.LastActivityDate
        $lastActivity = Get-SafeDate $lastActivityStr
        if ($lastActivity -and $lastActivity -ge $cutoffDate) {
            $activeTeams++
        }
        else {
            $inactiveTeams++
        }
    }

    # Channel and post totals
    $totalChannels = Sum-ColumnAsInt64 -data $teams -columnName 'ChannelCount'
    $totalPosts = Sum-ColumnAsInt64 -data $teams -columnName 'PostCount'
    $totalMembers = Sum-ColumnAsInt64 -data $teams -columnName 'MemberCount'

    # Find most active teams (top 10 by PostCount)
    $top10 = $teams | Where-Object { $_.PostCount -match '^\d+' } |
    Sort-Object { [int64]$_.PostCount } -Descending |
    Select-Object -First 10

    # Build primary summary metrics
    $metrics = [ordered]@{
        "Total Teams"                            = $totalTeams
        "Active Teams (Last $ActivityDays Days)" = $activeTeams
        "Inactive Teams"                         = $inactiveTeams
        "Total Channels"                         = $totalChannels
        "Total Posts/Messages"                   = $totalPosts
        "Total Members"                          = $totalMembers
    }

    # Determine insert position
    if ($InsertRange) {
        $range = $InsertRange
    }
    else {
        $range = $Document.Content
        $range.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)
    }

    # ========== PRIMARY SUMMARY TABLE ==========
    $range.InsertAfter("`r`n")
    $range.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)
    $caption = $range.Paragraphs.Add($range)
    $caption.Range.Text = $Title
    $caption.Style = "Caption"
    $caption.Range.InsertParagraphAfter()

    $numRows = $metrics.Count + 1
    $numCols = 2
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)
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

    $table.AutoFitBehavior([Microsoft.Office.Interop.Word.WdAutoFitBehavior]::wdAutoFitContent)

    if ($HeaderFontColor) {
        Set-AdHeaderFontColor -Table $table -Color $HeaderFontColor
    }

    # ========== TOP 10 MOST ACTIVE TEAMS TABLE ==========
    if ($top10.Count -gt 0) {
        $nextRange = $Document.Range($table.Range.End, $table.Range.End)
        $nextRange.InsertAfter("`r`n")
        $nextRange.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)

        $caption2 = $nextRange.Paragraphs.Add($nextRange)
        $caption2.Range.Text = "Top 10 Most Active Teams"
        $caption2.Style = "Caption"
        $caption2.Range.InsertParagraphAfter()

        $numRows2 = $top10.Count + 1
        $numCols2 = 5
        $tableRange2 = $caption2.Range.Next()
        $tableRange2.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)
        $table2 = $Document.Tables.Add($tableRange2, $numRows2, $numCols2)

        # Header
        $table2.Cell(1, 1).Range.Text = "Team Name"
        $table2.Cell(1, 2).Range.Text = "Channels"
        $table2.Cell(1, 3).Range.Text = "Posts/Messages"
        $table2.Cell(1, 4).Range.Text = "Members"
        $table2.Cell(1, 5).Range.Text = "Last Activity"
        $table2.Rows.Item(1).HeadingFormat = -1

        # Data rows
        $rowIndex2 = 2
        foreach ($team in $top10) {
            $table2.Cell($rowIndex2, 1).Range.Text = if ($team.TeamName) { $team.TeamName } else { "" }
            $table2.Cell($rowIndex2, 2).Range.Text = if ($team.ChannelCount) { $team.ChannelCount } else { "0" }
            $table2.Cell($rowIndex2, 3).Range.Text = if ($team.PostCount) { $team.PostCount } else { "0" }
            $table2.Cell($rowIndex2, 4).Range.Text = if ($team.MemberCount) { $team.MemberCount } else { "0" }
            $table2.Cell($rowIndex2, 5).Range.Text = if ($team.LastActivityDate) { $team.LastActivityDate } else { "" }
            $rowIndex2++
        }

        if ($TableStyleName) {
            $style2 = Get-AdWordTableStyle -Document $Document -StyleName $TableStyleName
            if ($style2) { $table2.Style = $style2 }
        }

        $table2.AutoFitBehavior([Microsoft.Office.Interop.Word.WdAutoFitBehavior]::wdAutoFitContent)

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
