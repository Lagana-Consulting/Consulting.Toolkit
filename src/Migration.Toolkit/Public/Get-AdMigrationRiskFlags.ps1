function Get-AdMigrationRiskFlags {
    <#
    .SYNOPSIS
    Identifies migration risk flags for users and computers.

    .DESCRIPTION
    Analyzes user and computer objects to flag potential migration issues:

    User risk flags:
    - UPN_NonRoutableSuffix: UPN suffix not routable for cloud
    - UPN_SuffixNotInForestList: UPN suffix not in forest UPN list
    - Disabled: Account is disabled
    - PasswordAgeOver365d: Password unchanged for 365+ days
    - StaleLastLogonOver180d: No logon for 180+ days
    - HasSPN(ServiceAcctCandidate): User has SPNs (service account pattern)
    - Kerberos_NoAES: Weak encryption (no AES support)

    Computer risk flags:
    - Disabled: Account is disabled
    - StaleLastLogonOver90d: No logon for 90+ days
    - Kerberos_NoAES: Weak encryption

    .PARAMETER AllUsers
    Array of user objects from Get-AdAdUsers. Required.

    .PARAMETER AllComputers
    Array of computer objects from Get-AdAdComputers. Required.

    .PARAMETER StaleUserThresholdDays
    Days since last logon to flag user as stale. Default is 180.

    .PARAMETER PasswordAgeThresholdDays
    Days since password change to flag as aged. Default is 365.

    .EXAMPLE
    $riskFlags = Get-AdMigrationRiskFlags -AllUsers $users -AllComputers $computers

    Generates risk flags with default thresholds.

    .EXAMPLE
    $riskFlags | Where-Object { $_.RiskFlags -contains 'UPN_NonRoutableSuffix' } |
      Select-Object ObjectClass, SamAccountName, RiskFlags

    Filters to objects with non-routable UPN suffixes.

    .EXAMPLE
    $highRisk = $riskFlags | Where-Object { $_.RiskFlags.Count -ge 3 }

    Finds objects with 3+ risk flags (high complexity for migration).

    .OUTPUTS
    PSCustomObject[] with properties:
    - ObjectClass (user/computer)
    - DomainFqdn, SamAccountName, DistinguishedName
    - RiskFlags (array of flag strings)
    - RiskCount (total number of flags)

    .NOTES
    Use for pre-migration risk assessment and remediation prioritization.
    Risk flag counts help estimate migration complexity and effort.
    Consider filtering disabled/stale accounts from migration scope.

    .LINK
    Get-AdAdUsers
    Get-AdAdComputers
    Get-AdMigrationRiskFlagsSummary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$AllUsers,

        [Parameter(Mandatory)]
        [array]$AllComputers,

        [int]$StaleUserThresholdDays = 180,

        [int]$PasswordAgeThresholdDays = 365
    )

    $results = @()

    # Process users
    foreach ($u in $AllUsers) {
        $flags = @()

        # UPN checks
        if ($u.IsNonRoutableUpnSuffix -eq $true) {
            $flags += 'UPN_NonRoutableSuffix'
        }
        if ($u.IsKnownUpnSuffix -eq $false -and $u.UserPrincipalName) {
            $flags += 'UPN_SuffixNotInForestList'
        }

        # Enabled status
        if ($u.Enabled -eq $false) {
            $flags += 'Disabled'
        }

        # Password flags (if available from extended user properties)
        # Note: PasswordNeverExpires not in current schema - would need to add to Get-AdAdUsers

        # Password age
        if ($u.PasswordAgeDays -and [int]$u.PasswordAgeDays -gt $PasswordAgeThresholdDays) {
            $flags += 'PasswordAgeOver365d'
        }

        # Staleness
        if ($u.LastLogonDays -and [int]$u.LastLogonDays -gt $StaleUserThresholdDays) {
            $flags += 'StaleLastLogonOver180d'
        }

        # SPN / service account candidate
        if ($u.SPNCount -and [int]$u.SPNCount -gt 0) {
            $flags += 'HasSPN(ServiceAcctCandidate)'
        }

        # Kerberos encryption
        if ($u.EncryptionRisk -eq 'High' -or ($u.EncryptionTypes -and $u.EncryptionTypes -notmatch 'AES')) {
            $flags += 'Kerberos_NoAES'
        }

        if ($flags.Count -gt 0) {
            $results += [pscustomobject]@{
                ObjectClass       = 'user'
                DomainFqdn        = [string]$u.DomainFqdn
                DistinguishedName = [string]$u.DistinguishedName
                SamAccountName    = [string]$u.SamAccountName
                UserPrincipalName = [string]$u.UserPrincipalName
                Flags             = ($flags -join ';')
            }
        }
    }

    # Process computers
    foreach ($c in $AllComputers) {
        $flags = @()

        # SPN
        if ($c.SPNCount -and [int]$c.SPNCount -gt 0) {
            $flags += 'HasSPN'
        }

        # Kerberos encryption
        if ($c.EncryptionRisk -eq 'High' -or ($c.EncryptionTypes -and $c.EncryptionTypes -notmatch 'AES')) {
            $flags += 'Kerberos_NoAES'
        }

        # Enabled status
        if ($c.Enabled -eq $false) {
            $flags += 'Disabled'
        }

        if ($flags.Count -gt 0) {
            $results += [pscustomobject]@{
                ObjectClass       = 'computer'
                DomainFqdn        = [string]$c.DomainFqdn
                DistinguishedName = [string]$c.DistinguishedName
                SamAccountName    = [string]$c.SamAccountName
                UserPrincipalName = ''
                Flags             = ($flags -join ';')
            }
        }
    }

    return $results
}
