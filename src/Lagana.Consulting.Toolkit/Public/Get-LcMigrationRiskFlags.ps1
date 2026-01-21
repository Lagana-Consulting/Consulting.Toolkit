function Get-LcMigrationRiskFlags {
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
        # Note: PasswordNeverExpires not in current schema - would need to add to Get-LcAdUsers

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
