function Get-AdDisabledAccounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllUsers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllComputers,

        [int]$StaleThresholdDays = 180
    )

    $results = @()

    # Process disabled users
    foreach ($u in $AllUsers) {
        if ($u.Enabled -eq $false) {
            $daysSinceChange = if ($u.WhenChanged) {
                [int]((Get-Date) - [datetime]$u.WhenChanged).TotalDays
            } else { 0 }

            $results += [pscustomobject]@{
                ObjectClass       = 'user'
                DomainFqdn        = [string]$u.DomainFqdn
                SamAccountName    = [string]$u.SamAccountName
                Name              = [string]$u.Name
                DistinguishedName = [string]$u.DistinguishedName
                WhenCreated       = $u.WhenCreated
                WhenChanged       = $u.WhenChanged
                DaysSinceChange   = $daysSinceChange
                CleanupCandidate  = if ($daysSinceChange -gt $StaleThresholdDays) { 'Yes' } else { 'No' }
            }
        }
    }

    # Process disabled computers
    foreach ($c in $AllComputers) {
        if ($c.Enabled -eq $false) {
            $daysSinceChange = if ($c.WhenChanged) {
                [int]((Get-Date) - [datetime]$c.WhenChanged).TotalDays
            } else { 0 }

            $results += [pscustomobject]@{
                ObjectClass       = 'computer'
                DomainFqdn        = [string]$c.DomainFqdn
                SamAccountName    = [string]$c.SamAccountName
                Name              = [string]$c.Name
                DistinguishedName = [string]$c.DistinguishedName
                WhenCreated       = $c.WhenCreated
                WhenChanged       = $c.WhenChanged
                DaysSinceChange   = $daysSinceChange
                CleanupCandidate  = if ($daysSinceChange -gt $StaleThresholdDays) { 'Yes' } else { 'No' }
            }
        }
    }

    return $results | Sort-Object -Property DaysSinceChange -Descending
}
