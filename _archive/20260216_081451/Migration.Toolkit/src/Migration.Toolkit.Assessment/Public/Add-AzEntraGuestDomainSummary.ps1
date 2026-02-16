function Add-AzEntraGuestDomainSummary {
    <#
  .SYNOPSIS
  Creates a summary table showing guest user counts grouped by email domain.

  .DESCRIPTION
  Analyzes Entra ID user CSV data to identify guest accounts (UserType = Guest) and
  groups them by email domain. Creates a table showing domain names and guest counts,
  sorted by count descending. Useful for understanding external collaboration patterns.

  Expects CSV columns like: UserPrincipalName, UserType, Mail

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER CsvPath
  Path to the CSV file containing Entra ID user data.

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .PARAMETER TopN
  Number of top domains to display. Defaults to all domains. Use -TopN 20 for top 20.

  .EXAMPLE
  Add-AdEntraGuestDomainSummary -Document $word.ActiveDocument `
    -Title "Guest Users by Email Domain" `
    -CsvPath "C:\data\Entra_Users.csv" `
    -TableStyleName "Grid Table 4 - Accent 1" `
    -TopN 20

  Shows the top 20 guest domains by user count.

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

        [int]$TopN = 0
    )

    # Import user data
    $users = Import-Csv -Path $CsvPath -ErrorAction Stop
    if (-not $users -or $users.Count -eq 0) {
        Write-Warning "CSV file $CsvPath is empty or has no data rows."
        return $InsertRange
    }

    # Filter guest users (UserType = Guest)
    $guests = $users | Where-Object {
        $_.UserType -eq 'Guest' -or
        $_.UserType -eq 'guest' -or
        ($_.UserPrincipalName -like '*#EXT#*')  # Alternative guest detection
    }

    if (-not $guests -or $guests.Count -eq 0) {
        Write-Warning "No guest users found in CSV file."
        return $InsertRange
    }

    # Extract email domains from UPN or Mail column
    $domainCounts = @{}
    foreach ($guest in $guests) {
        $email = $guest.UserPrincipalName
        if ([string]::IsNullOrWhiteSpace($email) -and $guest.Mail) {
            $email = $guest.Mail
        }

        if ([string]::IsNullOrWhiteSpace($email)) {
            continue
        }

        # Extract domain from email (handle #EXT# format)
        $domain = ""
        if ($email -match '@([^#@]+)') {
            $domain = $matches[1].Trim().ToLower()
        }
        elseif ($email -match '_([^_]+)#EXT#') {
            $domain = $matches[1].Trim().ToLower()
        }

        if (-not [string]::IsNullOrWhiteSpace($domain)) {
            if ($domainCounts.ContainsKey($domain)) {
                $domainCounts[$domain]++
            }
            else {
                $domainCounts[$domain] = 1
            }
        }
    }

    if ($domainCounts.Count -eq 0) {
        Write-Warning "No valid email domains extracted from guest users."
        return $InsertRange
    }

    # Sort by count descending
    $sortedDomains = $domainCounts.GetEnumerator() | Sort-Object Value -Descending

    # Apply TopN filter if specified
    if ($TopN -gt 0) {
        $sortedDomains = $sortedDomains | Select-Object -First $TopN
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
    $numRows = $sortedDomains.Count + 1  # +1 for header
    $numCols = 2
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)

    # Header row
    $table.Cell(1, 1).Range.Text = "Email Domain"
    $table.Cell(1, 2).Range.Text = "Guest Count"
    $table.Rows.Item(1).HeadingFormat = -1

    # Data rows
    $rowIndex = 2
    foreach ($entry in $sortedDomains) {
        $table.Cell($rowIndex, 1).Range.Text = $entry.Key
        $table.Cell($rowIndex, 2).Range.Text = $entry.Value
        $rowIndex++
    }

    # Apply table style
    if ($TableStyleName) {
        $style = Get-AdWordTableStyle -Document $Document -StyleName $TableStyleName
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
