function Get-AdDisabledAccounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllUsers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllComputers,

        [ValidateRange(0, [int]::MaxValue)][int]$StaleThresholdDays = 180
    )

    $results = @()
    $now = [datetime]::UtcNow

    # Process disabled users
    foreach ($u in $AllUsers) {
        if ((ConvertTo-AdAssessmentBoolean $u.Enabled -Field 'Enabled') -eq $false) {
            $changedUtc = ConvertTo-AdAssessmentUtcDate $u.WhenChanged -Field 'WhenChanged'
            $daysSinceChange = Get-AdDaysSince -DateUtc $changedUtc -Now $now

            $results += [pscustomobject]@{
                ObjectClass       = 'user'
                DomainFqdn        = [string]$u.DomainFqdn
                SamAccountName    = [string]$u.SamAccountName
                Name              = [string]$u.Name
                DistinguishedName = [string]$u.DistinguishedName
                WhenCreated       = $u.WhenCreated
                WhenChanged       = $u.WhenChanged
                DaysSinceChange   = $daysSinceChange
                CleanupCandidate  = if ($null -eq $daysSinceChange) { 'Unknown' } elseif ($daysSinceChange -gt $StaleThresholdDays) { 'Yes' } else { 'No' }
            }
        }
    }

    # Process disabled computers
    foreach ($c in $AllComputers) {
        if ((ConvertTo-AdAssessmentBoolean $c.Enabled -Field 'Enabled') -eq $false) {
            $changedUtc = ConvertTo-AdAssessmentUtcDate $c.WhenChanged -Field 'WhenChanged'
            $daysSinceChange = Get-AdDaysSince -DateUtc $changedUtc -Now $now

            $results += [pscustomobject]@{
                ObjectClass       = 'computer'
                DomainFqdn        = [string]$c.DomainFqdn
                SamAccountName    = [string]$c.SamAccountName
                Name              = [string]$c.Name
                DistinguishedName = [string]$c.DistinguishedName
                WhenCreated       = $c.WhenCreated
                WhenChanged       = $c.WhenChanged
                DaysSinceChange   = $daysSinceChange
                CleanupCandidate  = if ($null -eq $daysSinceChange) { 'Unknown' } elseif ($daysSinceChange -gt $StaleThresholdDays) { 'Yes' } else { 'No' }
            }
        }
    }

    return $results | Sort-Object -Property DaysSinceChange -Descending
}
