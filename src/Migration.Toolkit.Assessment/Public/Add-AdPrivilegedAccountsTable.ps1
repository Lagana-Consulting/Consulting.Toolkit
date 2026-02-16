function Add-AdPrivilegedAccountsTable {
    <#
  .SYNOPSIS
  Creates a table showing privileged accounts in the domain.

  .DESCRIPTION
  Displays accounts with elevated privileges based on:
  - AdminCount attribute
  - Group membership (Domain Admins, Enterprise Admins, etc.)
  - Sensitive permissions
  - Protected accounts (AdminSDHolder impact)

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to privileged accounts CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .PARAMETER Columns
  Optional column filtering/renaming. Default columns:
  SamAccountName, Name, Enabled, AdminCount, MemberOf, LastLogonDays

  .PARAMETER Mode
  'Summary' = Count by privilege type
  'Detail' (default) = Full listing of privileged accounts

  .EXAMPLE
  Add-AdPrivilegedAccountsTable -Document $doc -Title "Privileged Accounts" `
    -CsvPath "PrivilegedAccounts.csv" -TableStyleName "Light Grid Accent 1"

  .EXAMPLE
  $cols = [ordered]@{
    Account="SamAccountName"
    Status="Enabled"
    "Admin Count"="AdminCount"
    "Last Logon (Days)"="LastLogonDays"
  }
  Add-AdPrivilegedAccountsTable -Document $doc -Title "Admin Accounts" `
    -CsvPath "PrivilegedAccounts.csv" -Columns $cols -Mode Detail
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $CsvPath,
        [Parameter(Mandatory)][string] $TableStyleName,
        $InsertRange = $null,
        [string] $HeaderFontColor,
        [object] $Columns,
        [ValidateSet('Summary', 'Detail')][string] $Mode = 'Detail'
    )

    if (-not (Test-Path $CsvPath)) {
        Write-Warning "CSV not found: $CsvPath"
        return $InsertRange
    }

    $data = Import-Csv $CsvPath
    if (-not $data -or $data.Count -eq 0) {
        Write-Warning "No privileged accounts data found in: $CsvPath"
        return $InsertRange
    }

    if ($Mode -eq 'Summary') {
        # Summary: counts by privilege type (if PrivilegeSource or similar column exists)
        # Otherwise just show total count

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

        # Simple 2-column summary
        $metrics = [ordered]@{
            "Total Privileged Accounts" = $data.Count
            "Enabled Accounts"          = ($data | Where-Object { $_.Enabled -eq "True" }).Count
            "Disabled Accounts"         = ($data | Where-Object { $_.Enabled -eq "False" }).Count
            "With AdminCount=1"         = ($data | Where-Object { $_.AdminCount -eq "1" }).Count
        }

        $rows = $metrics.Count + 1
        $cols = 2

        $table = $Document.Tables.Add($afterHeading, $rows, $cols)
        $table.Range.Style = "Normal"

        $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
        if ($style) { $table.Style = $style }

        # Headers
        $table.Cell(1, 1).Range.Text = "Metric"
        $table.Cell(1, 1).Range.Bold = $true
        Set-AdHeaderFontColor -Range $table.Cell(1, 1).Range -HeaderFontColor $HeaderFontColor

        $table.Cell(1, 2).Range.Text = "Value"
        $table.Cell(1, 2).Range.Bold = $true
        Set-AdHeaderFontColor -Range $table.Cell(1, 2).Range -HeaderFontColor $HeaderFontColor

        # Data
        $r = 2
        foreach ($key in $metrics.Keys) {
            $table.Cell($r, 1).Range.Text = $key
            $table.Cell($r, 2).Range.Text = [string]$metrics[$key]
            $r++
        }

        $table.Range.InsertParagraphAfter() | Out-Null
        $nextRange = $table.Range.Duplicate()
        $nextRange.Collapse(0) | Out-Null
        return $nextRange
    }
    else {
        # Detail mode - raw table
        if (-not $Columns) {
            $Columns = [ordered]@{
                "Account"           = "SamAccountName"
                "Name"              = "Name"
                "Enabled"           = "Enabled"
                "Admin Count"       = "AdminCount"
                "Last Logon (Days)" = "LastLogonDays"
            }
        }

        $params = @{
            Document       = $Document
            Title          = $Title
            CsvPath        = $CsvPath
            TableStyleName = $TableStyleName
            Columns        = $Columns
        }
        if ($InsertRange) { $params.InsertRange = $InsertRange }
        if ($HeaderFontColor) { $params.HeaderFontColor = $HeaderFontColor }

        return Add-AdRawTableFromCsv @params
    }
}
