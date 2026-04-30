function Add-AdEmptyGroupsTable {
    <#
  .SYNOPSIS
  Creates a table showing empty AD groups (groups with no members).

  .DESCRIPTION
  Analyzes empty groups CSV and creates either a pivot summary (groups by category/scope)
  or a raw table listing all empty groups.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to empty groups CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .PARAMETER Mode
  'Summary' (default) = Pivot table by GroupCategory/GroupScope showing counts
  'Detail' = Raw table listing all empty groups with names

  .PARAMETER Columns
  Optional column filtering/renaming for Detail mode.

  .EXAMPLE
  Add-AdEmptyGroupsTable -Document $doc -Title "Empty Groups Summary" `
    -CsvPath "EmptyGroups.csv" -TableStyleName "Light Grid Accent 1" -Mode Summary

  .EXAMPLE
  Add-AdEmptyGroupsTable -Document $doc -Title "Empty Groups Detail" `
    -CsvPath "EmptyGroups.csv" -Mode Detail `
    -Columns @{Name="SamAccountName"; "Group Type"="GroupCategory"; Scope="GroupScope"}
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [string] $CsvPath,
        [string] $DomainFolderPath,
        [Parameter(Mandatory)][string] $TableStyleName,
        $InsertRange = $null,
        [string] $HeaderFontColor,
        [ValidateSet('Summary', 'Detail')][string] $Mode = 'Summary',
        [object] $Columns
    )

    if ($CsvPath -and (Test-Path $CsvPath)) {
        $data = Import-Csv $CsvPath
        if (-not $data -or $data.Count -eq 0) {
            Write-Warning "No empty groups data found in: $CsvPath"
            return $InsertRange
        }
    }
    elseif ($DomainFolderPath -and (Test-Path $DomainFolderPath)) {
        $groups = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Identity__Groups__*.csv')
        $metrics = [ordered]@{
            "Status" = "Not derivable from current offline discovery output"
            "Groups Inventoried" = [string]@($groups).Count
            "Reason" = "The current discovery export does not include group membership or member counts."
            "Recommended Next Step" = "Enhance the collector to export group membership so empty groups can be identified offline."
        }

        if ($InsertRange) {
            $currentRange = $InsertRange.Duplicate()
        }
        else {
            $currentRange = $Document.Range()
            $currentRange.Collapse(0) | Out-Null
        }

        $hRange = $currentRange.Duplicate()
        $para = $hRange.Paragraphs.Add()
        $para.Range.Text = $Title
        $para.Range.Style = "Caption"
        $para.Range.InsertParagraphAfter() | Out-Null

        $afterHeadingRange = $para.Range.Duplicate()
        $afterHeadingRange.Collapse(0) | Out-Null

        $table = $Document.Tables.Add($afterHeadingRange, $metrics.Count + 1, 2)
        $table.Range.Style = "Normal"

        $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
        if ($style) { $table.Style = $style }

        $table.Cell(1, 1).Range.Text = "Metric"
        $table.Cell(1, 1).Range.Bold = $true
        $table.Cell(1, 2).Range.Text = "Value"
        $table.Cell(1, 2).Range.Bold = $true
        $table.Rows.Item(1).HeadingFormat = -1

        if ($HeaderFontColor) {
            Set-AdHeaderFontColor -Table $table -Color $HeaderFontColor
        }

        $rowIndex = 2
        foreach ($key in $metrics.Keys) {
            $table.Cell($rowIndex, 1).Range.Text = [string]$key
            $table.Cell($rowIndex, 2).Range.Text = [string]$metrics[$key]
            $rowIndex++
        }

        $table.AutoFitBehavior(1)
        $table.Range.InsertParagraphAfter() | Out-Null

        $nextRange = $table.Range.Duplicate()
        $nextRange.Collapse(0) | Out-Null
        return $nextRange
    }
    else {
        Write-Warning "Either CsvPath or DomainFolderPath must be provided for empty group analysis."
        return $InsertRange
    }

    if ($Mode -eq 'Summary') {
        # Pivot: Count by GroupCategory and GroupScope
        $pivotData = $data | Group-Object GroupCategory, GroupScope | ForEach-Object {
            $parts = $_.Name -split ', '
            [pscustomobject]@{
                GroupCategory = $parts[0]
                GroupScope    = $parts[1]
                Count         = $_.Count
            }
        } | Sort-Object GroupCategory, GroupScope

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

        $afterHeading = $para.Range.Duplicate()
        $afterHeading.Collapse(0) | Out-Null

        $rows = $pivotData.Count + 1
        $cols = 3

        $table = $Document.Tables.Add($afterHeading, $rows, $cols)
        $table.Range.Style = "Normal"

        $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
        if ($style) { $table.Style = $style }

        # Headers
        $headers = @("Group Category", "Group Scope", "Count")
        for ($c = 0; $c -lt $cols; $c++) {
            $cell = $table.Cell(1, $c + 1).Range
            $cell.Text = $headers[$c]
            $cell.Bold = $true
            Set-AdHeaderFontColor -Range $cell -HeaderFontColor $HeaderFontColor
        }

        # Data
        $r = 2
        foreach ($row in $pivotData) {
            $table.Cell($r, 1).Range.Text = $row.GroupCategory
            $table.Cell($r, 2).Range.Text = $row.GroupScope
            $table.Cell($r, 3).Range.Text = [string]$row.Count
            $r++
        }

        $table.Range.InsertParagraphAfter() | Out-Null
        $nextRange = $table.Range.Duplicate()
        $nextRange.Collapse(0) | Out-Null
        return $nextRange
    }
    else {
        # Detail mode - raw table
        $params = @{
            Document       = $Document
            Title          = $Title
            CsvPath        = $CsvPath
            TableStyleName = $TableStyleName
        }
        if ($InsertRange) { $params.InsertRange = $InsertRange }
        if ($HeaderFontColor) { $params.HeaderFontColor = $HeaderFontColor }
        if ($Columns) { $params.Columns = $Columns }

        return Add-AdRawTableFromCsv @params
    }
}
