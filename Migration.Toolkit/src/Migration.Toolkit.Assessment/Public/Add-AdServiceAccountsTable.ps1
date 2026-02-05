function Add-AdServiceAccountsTable {
    <#
  .SYNOPSIS
  Creates a table showing service account candidates identified during discovery.

  .DESCRIPTION
  Displays accounts flagged as potential service accounts based on criteria like:
  - ServicePrincipalName count
  - PasswordNeverExpires
  - Account naming patterns
  - Interactive logon restrictions

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to service account candidates CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .PARAMETER Columns
  Optional column filtering/renaming. Default columns:
  SamAccountName, Name, Enabled, SPNCount, PasswordNeverExpires, LastLogonDays

  .EXAMPLE
  Add-AdServiceAccountsTable -Document $doc -Title "Service Account Candidates" `
    -CsvPath "ServiceAccountCandidates.csv" -TableStyleName "Light Grid Accent 1"

  .EXAMPLE
  $cols = [ordered]@{
    Account="SamAccountName"
    Status="Enabled"
    SPNs="SPNCount"
    "Last Logon (Days)"="LastLogonDays"
  }
  Add-AdServiceAccountsTable -Document $doc -Title "Service Accounts" `
    -CsvPath "ServiceAccounts.csv" -Columns $cols
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $CsvPath,
        [Parameter(Mandatory)][string] $TableStyleName,
        $InsertRange = $null,
        [string] $HeaderFontColor,
        [object] $Columns
    )

    if (-not (Test-Path $CsvPath)) {
        Write-Warning "CSV not found: $CsvPath"
        return $InsertRange
    }

    # Default columns if not specified
    if (-not $Columns) {
        $Columns = [ordered]@{
            "Account"                   = "SamAccountName"
            "Name"                      = "Name"
            "Enabled"                   = "Enabled"
            "SPN Count"                 = "SPNCount"
            "Password Never Expires"    = "PasswordNeverExpires"
            "Last Logon (Days)"         = "LastLogonDays"
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
