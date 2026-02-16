function Add-AzEntraUserSummary {
    <#
  .SYNOPSIS
  Creates an Entra ID user summary table with member/guest/sync/license metrics.

  .DESCRIPTION
  Analyzes Entra ID user CSV data to calculate counts of members, guests,
  enabled/disabled, hybrid-synced, cloud-only, and stale accounts.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to Entra users CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .EXAMPLE
  Add-AdEntraUserSummary -Document $doc -Title "Entra User Summary" -CsvPath "Entra_Users.csv" -TableStyleName "Light Grid Accent 1"
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
        Write-Warning "Entra users CSV not found: $CsvPath"
        return $InsertRange
    }

    $users = Import-Csv $CsvPath

    if ($users.Count -eq 0) {
        Write-Warning "Entra user CSV '$CsvPath' is empty."
        return $InsertRange
    }

    # Basic counts
    $totalUsers = $users.Count
    $members = ($users | Where-Object { $_.UserType -eq "Member" }).Count
    $guests = ($users | Where-Object { $_.UserType -eq "Guest" }).Count

    $enabled = ($users | Where-Object { $_.AccountEnabled -eq "True" }).Count
    $disabled = ($users | Where-Object { $_.AccountEnabled -eq "False" }).Count

    # Missing usage location
    $noUsageLoc = ($users | Where-Object { [string]::IsNullOrWhiteSpace($_.UsageLocation) }).Count

    # Last sign-in
    $now = Get-Date
    $stale90 = ($users | Where-Object {
            $_."SignInActivity.LastSignInDateTime" -and
            ((Get-Date $_."SignInActivity.LastSignInDateTime") -lt $now.AddDays(-90))
        }).Count

    # Recently created
    $created30 = ($users | Where-Object {
            $_.CreatedDateTime -and
            ((Get-Date $_.CreatedDateTime) -gt $now.AddDays(-30))
        }).Count

    # Hybrid sync
    $hybridSynced = ($users | Where-Object { $_.OnPremisesSyncEnabled -eq "True" -or $_.DirSyncEnabled -eq "True" }).Count
    $cloudOnly = $totalUsers - $hybridSynced

    # Summary
    $summary = [ordered]@{
        "Total Entra Accounts"        = $totalUsers
        "Enabled Accounts"            = $enabled
        "Disabled Accounts"           = $disabled
        "Member Users"                = $members
        "Guest Users"                 = $guests
        "Missing UsageLocation"       = $noUsageLoc
        "Stale (>90 days no sign-in)" = $stale90
        "Created in Last 30 Days"     = $created30
        "Hybrid-Synced Accounts"      = $hybridSynced
        "Cloud-only Accounts"         = $cloudOnly
    }

    return Add-AdSimpleSummaryTable -Document $Document `
        -Title $Title `
        -Data $summary `
        -TableStyleName $TableStyleName `
        -InsertRange $InsertRange `
        -HeaderFontColor $HeaderFontColor
}
