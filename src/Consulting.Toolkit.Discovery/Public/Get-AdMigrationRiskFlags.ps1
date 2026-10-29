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
    - LegacyWorkstationOS: Windows XP/Vista/7/8/2000
    - LegacyServerOS: Windows Server 2003/2008/2008 R2/2012/2012 R2

    .PARAMETER AllUsers
    Array of user objects from Get-AdAdUsers. Required.

    .PARAMETER AllComputers
    Array of computer objects from Get-AdAdComputers. Required.

    .PARAMETER StaleUserThresholdDays
    Days since last logon to flag user as stale. Default is 180.

    .PARAMETER PasswordAgeThresholdDays
    Days since password change to flag as aged. Default is 365.

    .PARAMETER LegacyWorkstationOsRegex
    Regex pattern to identify legacy workstation OS versions. Default matches Windows XP, Vista, 7, 8, 8.1, 2000.

    .PARAMETER LegacyServerOsRegex
    Regex pattern to identify legacy server OS versions. Default matches Windows Server 2003, 2008, 2008 R2, 2012, 2012 R2.

    .EXAMPLE
    $riskFlags = Get-AdMigrationRiskFlags -AllUsers $users -AllComputers $computers

    Generates risk flags with default thresholds.

    .EXAMPLE
    $riskFlags | Where-Object { ($_.Flags -split ';') -contains 'UPN_NonRoutableSuffix' } |
      Select-Object ObjectClass, SamAccountName, Flags

    Filters to objects with non-routable UPN suffixes.

    .EXAMPLE
    $highRisk = $riskFlags | Where-Object { @($_.Flags -split ';').Count -ge 3 }

    Finds objects with 3+ risk flags (high complexity for migration).

    .OUTPUTS
    PSCustomObject[] with properties:
    - ObjectClass (user/computer)
    - DomainFqdn, SamAccountName, DistinguishedName
    - UserPrincipalName (blank for computers)
    - Flags (semicolon-delimited flag strings)

    .NOTES
    Use for pre-migration risk assessment and remediation prioritization.
    Kerberos_NoAES requires explicit DES or RC4 capability without AES.
    Unset encryption capabilities and blank Boolean states remain unknown.
    Consider filtering disabled/stale accounts from migration scope.

    .LINK
    Get-AdAdUsers
    Get-AdAdComputers
    Get-AdMigrationRiskFlagsSummary
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllUsers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllComputers,

        [ValidateRange(0, [int]::MaxValue)][int]$StaleUserThresholdDays = 180,

        [ValidateRange(0, [int]::MaxValue)][int]$PasswordAgeThresholdDays = 365,

        [string]$LegacyWorkstationOsRegex = '(?i)Windows (XP|Vista|7|8|8\.1|2000)',

        [string]$LegacyServerOsRegex = '(?i)Windows Server (2003|2008|2008 R2|2012|2012 R2)'
    )

    $results = @()

    # Process users
    foreach ($u in $AllUsers) {
        $flags = @()

        # UPN checks
        if ((ConvertTo-AdAssessmentBoolean $u.IsNonRoutableUpnSuffix -Field 'IsNonRoutableUpnSuffix') -eq $true) {
            $flags += 'UPN_NonRoutableSuffix'
        }
        if ((ConvertTo-AdAssessmentBoolean $u.IsKnownUpnSuffix -Field 'IsKnownUpnSuffix') -eq $false -and $u.UserPrincipalName) {
            $flags += 'UPN_SuffixNotInForestList'
        }

        # Enabled status
        if ((ConvertTo-AdAssessmentBoolean $u.Enabled -Field 'Enabled') -eq $false) {
            $flags += 'Disabled'
        }

        # Password flags (if available from extended user properties)
        # Note: PasswordNeverExpires not in current schema - would need to add to Get-AdAdUsers

        # Password age
        if ((ConvertTo-AdAssessmentInteger $u.PasswordAgeDays -Field 'PasswordAgeDays') -gt $PasswordAgeThresholdDays) {
            $flags += 'PasswordAgeOver365d'
        }

        # Staleness
        if ((ConvertTo-AdAssessmentInteger $u.LastLogonDays -Field 'LastLogonDays') -gt $StaleUserThresholdDays) {
            $flags += 'StaleLastLogonOver180d'
        }

        # SPN / service account candidate
        if ((ConvertTo-AdAssessmentInteger $u.SPNCount -Field 'SPNCount') -gt 0) {
            $flags += 'HasSPN(ServiceAcctCandidate)'
        }

        # Kerberos encryption
        if ((Get-AdAssessmentEncryptionState $u.EncryptionTypes).NoAes) {
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
        if ((ConvertTo-AdAssessmentInteger $c.SPNCount -Field 'SPNCount') -gt 0) {
            $flags += 'HasSPN'
        }

        # Kerberos encryption
        if ((Get-AdAssessmentEncryptionState $c.EncryptionTypes).NoAes) {
            $flags += 'Kerberos_NoAES'
        }

        # Enabled status
        if ((ConvertTo-AdAssessmentBoolean $c.Enabled -Field 'Enabled') -eq $false) {
            $flags += 'Disabled'
        }

        # Stale logon
        if ((ConvertTo-AdAssessmentInteger $c.LastLogonDays -Field 'LastLogonDays') -gt 90) {
            $flags += 'StaleLastLogonOver90d'
        }

        # Legacy OS detection
        $isServer = ConvertTo-AdAssessmentBoolean $c.IsServer -Field 'IsServer'
        if ($isServer -eq $true -and $c.OperatingSystem -match $LegacyServerOsRegex) {
            $flags += 'LegacyServerOS'
        }
        elseif ($isServer -eq $false -and $c.OperatingSystem -match $LegacyWorkstationOsRegex) {
            $flags += 'LegacyWorkstationOS'
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
