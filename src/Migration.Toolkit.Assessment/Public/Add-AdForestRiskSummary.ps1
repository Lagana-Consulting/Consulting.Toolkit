function Add-AdForestRiskSummary {
    <#
  .SYNOPSIS
  Creates a forest-level risk summary table showing risk flag counts by object class.

  .DESCRIPTION
  Generates a table from the forest risk flags summary CSV showing the count of
  objects with each risk flag type (e.g., StaleLastLogonOver90d, Disabled, PasswordAgeOver365d)
  grouped by object class (user, computer, group).

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the forest risk flags summary CSV file (AD__Migration__RiskFlagsSummary__Forest.csv).

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .EXAMPLE
  Add-AdForestRiskSummary -Document $word.ActiveDocument `
    -Title "Forest Risk Summary" `
    -CsvPath "C:\data\AD__Migration__RiskFlagsSummary__Forest.csv" `
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

        [string]$CsvPath,

        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$DiscoveryOutputPath,

        [string]$TableStyleName,

        [__ComObject]$InsertRange,

        $HeaderFontColor
    )

    # Import risk summary data
    if ($CsvPath) {
        $riskData = Import-Csv -Path $CsvPath -ErrorAction Stop
    }
    elseif ($DiscoveryOutputPath) {
        $riskData = Get-AdAssessmentForestRiskSummaryData -DiscoveryOutputPath $DiscoveryOutputPath
    }
    else {
        throw "Either CsvPath or DiscoveryOutputPath must be provided."
    }

    if (-not $riskData -or $riskData.Count -eq 0) {
        Write-Warning "No forest risk summary data was available to render."
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
    $numCols = 3
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)

    # Set table content style to Normal before applying table style
    $table.Range.Style = "Normal"

    # Header row
    $table.Cell(1, 1).Range.Text = "Risk Flag"
    $table.Cell(1, 2).Range.Text = "Object Type"
    $table.Cell(1, 3).Range.Text = "Count"
    $table.Rows.Item(1).HeadingFormat = -1

    # Data rows
    $rowIndex = 2
    foreach ($row in $riskData) {
        $table.Cell($rowIndex, 1).Range.Text = [string]$row.Flag
        $table.Cell($rowIndex, 2).Range.Text = [string]$row.ObjectClass
        $table.Cell($rowIndex, 3).Range.Text = [string]$row.Count
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
