function Add-AdUserStatsSummary {
    <#
  .SYNOPSIS
  Creates an AD user statistics summary table with enabled/disabled/stale/password metrics.

  .DESCRIPTION
  Analyzes AD user CSV data to calculate counts of enabled, disabled, stale users,
  and password never expires. Produces a metric/value summary table.

  .PARAMETER Document
  Word document object.

  .PARAMETER Title
  Table caption/title.

  .PARAMETER CsvPath
  Path to AD users CSV export.

  .PARAMETER TableStyleName
  Word table style to apply.

  .PARAMETER InsertRange
  Optional Word range where table should be inserted.

  .PARAMETER HeaderFontColor
  Optional color for header row.

  .PARAMETER StaleDays
  Number of days since last logon to consider a user stale (default 90).

  .EXAMPLE
  Add-AdUserStatsSummary -Document $doc -Title "AD User Summary" -CsvPath "AD_Users.csv" -TableStyleName "Light Grid Accent 1" -StaleDays 90
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $CsvPath,
        [Parameter(Mandatory)][string] $TableStyleName,
        $InsertRange = $null,
        [string] $HeaderFontColor,
        [int] $StaleDays = 90
    )

    if (-not (Test-Path $CsvPath)) {
        Write-Warning "AD User CSV not found: $CsvPath"
        return $InsertRange
    }

    $users = Import-Csv $CsvPath
    if (-not $users -or $users.Count -eq 0) {
        Write-Warning "AD User CSV '$CsvPath' is empty."
        return $InsertRange
    }

    # Helper: truthy parsing
    function Test-Truthy([object]$v) {
        if ($null -eq $v) { return $false }
        $s = ([string]$v).Trim()
        return @('true', '1', 'yes', 'y') -contains $s.ToLowerInvariant()
    }

    # Helper: get first existing property value
    function Get-PropValue($obj, [string[]]$names) {
        foreach ($n in $names) {
            if ($obj.PSObject.Properties.Name -contains $n) { return $obj.$n }
        }
        return $null
    }

    # Determine column name variations
    $enabledColCandidates = @('Enabled', 'AccountEnabled')
    $pneColCandidates = @('PasswordNeverExpires', 'PwdNeverExpires', 'Password Never Expires')
    $lastLogonCandidates = @('LastLogonDate', 'LastLogon', 'LastLogonTimestamp', 'Last Sign-In', 'LastSignInDate')

    $now = Get-Date
    $staleCutoff = $now.AddDays(-$StaleDays)

    $total = $users.Count
    $enabled = 0
    $disabled = 0
    $pwdNeverExpires = 0
    $stale = 0

    foreach ($u in $users) {
        $isEnabled = Test-Truthy (Get-PropValue $u $enabledColCandidates)
        if ($isEnabled) { $enabled++ } else { $disabled++ }

        $pne = Test-Truthy (Get-PropValue $u $pneColCandidates)
        if ($pne) { $pwdNeverExpires++ }

        $last = Get-PropValue $u $lastLogonCandidates
        if ($null -eq $last -or ([string]$last).Trim() -eq "") {
            $stale++
        }
        else {
            try {
                $lastDate = Get-Date $last
                if ($lastDate -lt $staleCutoff) { $stale++ }
            }
            catch {
                $stale++
            }
        }
    }

    $summary = [ordered]@{
        "Total AD Users"                 = $total
        "Enabled Users"                  = $enabled
        "Disabled Users"                 = $disabled
        "Stale Users ($StaleDays+ days)" = $stale
        "Password Never Expires"         = $pwdNeverExpires
    }

    return Add-AdSimpleSummaryTable -Document $Document `
        -Title $Title `
        -Data $summary `
        -TableStyleName $TableStyleName `
        -InsertRange $InsertRange `
        -HeaderFontColor $HeaderFontColor
}
