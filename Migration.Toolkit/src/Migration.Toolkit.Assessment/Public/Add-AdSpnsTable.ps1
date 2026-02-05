function Add-AdSpnsTable {
    <#
  .SYNOPSIS
  Creates a table showing Service Principal Names (SPNs) registered in the domain.

  .DESCRIPTION
  Displays SPNs assigned to user and computer accounts, useful for identifying:
  - Kerberos-enabled services
  - Service account usage
  - Potential delegation issues
  - Duplicate SPNs

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to SPNs CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .PARAMETER Columns
  Optional column filtering/renaming. Default columns:
  SamAccountName, ObjectClass, ServicePrincipalName, SPNType (if available)

  .PARAMETER Top
  Optional limit to show only top N SPNs by some criteria.

  .EXAMPLE
  Add-AdSpnsTable -Document $doc -Title "Service Principal Names" `
    -CsvPath "SPNs.csv" -TableStyleName "Light Grid Accent 1"

  .EXAMPLE
  $cols = [ordered]@{
    Account="SamAccountName"
    Type="ObjectClass"
    SPN="ServicePrincipalName"
  }
  Add-AdSpnsTable -Document $doc -Title "Registered SPNs" `
    -CsvPath "SPNs.csv" -Columns $cols -Top 50
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
        [int] $Top
    )

    if (-not (Test-Path $CsvPath)) {
        Write-Warning "CSV not found: $CsvPath"
        return $InsertRange
    }

    $data = Import-Csv $CsvPath
    if (-not $data -or $data.Count -eq 0) {
        Write-Warning "No SPN data found in: $CsvPath"
        return $InsertRange
    }

    # Apply Top filter if specified
    if ($Top -gt 0) {
        $data = $data | Select-Object -First $Top
    }

    # Default columns if not specified
    if (-not $Columns) {
        $Columns = [ordered]@{
            "Account"                = "SamAccountName"
            "Type"                   = "ObjectClass"
            "Service Principal Name" = "ServicePrincipalName"
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

    # If Top specified, need to export filtered data to temp CSV
    if ($Top -gt 0) {
        $tempCsv = [System.IO.Path]::GetTempFileName() + ".csv"
        $data | Export-Csv -Path $tempCsv -NoTypeInformation
        $params.CsvPath = $tempCsv

        try {
            return Add-AdRawTableFromCsv @params
        }
        finally {
            if (Test-Path $tempCsv) {
                Remove-Item $tempCsv -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        return Add-AdRawTableFromCsv @params
    }
}
