function Get-AdUserStatusDetails {
    <#
    .SYNOPSIS
    Splits discovered user rows into disabled and inactive user datasets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Users,

        [int]$InactiveDays = 180
    )

    $disabledUsers = New-Object System.Collections.Generic.List[object]
    $inactiveUsers = New-Object System.Collections.Generic.List[object]

    foreach ($user in @($Users)) {
        $enabled = ConvertTo-AdUserStatusBoolean -Value $user.Enabled -Default $true
        $lastLogonDays = ConvertTo-AdUserStatusNullableInt -Value $user.LastLogonDays

        $row = [pscustomobject]@{
            DomainFqdn                   = [string]$user.DomainFqdn
            SamAccountName               = [string]$user.SamAccountName
            Name                         = [string]$user.Name
            DistinguishedName            = [string]$user.DistinguishedName
            Enabled                      = [bool]$enabled
            UserPrincipalName            = [string]$user.UserPrincipalName
            Mail                         = [string]$user.Mail
            WhenCreated                  = $user.WhenCreated
            WhenChanged                  = $user.WhenChanged
            LastLogonTimestampUtc        = $user.LastLogonTimestampUtc
            LastLogonDays                = if ($null -eq $lastLogonDays) { '' } else { [string]$lastLogonDays }
            InactiveThresholdDays        = $InactiveDays
            PasswordLastSetUtc           = $user.PasswordLastSetUtc
            PasswordAgeDays              = $user.PasswordAgeDays
            AdminCount                   = $user.AdminCount
            SidHistoryCount              = $user.SidHistoryCount
            SPNCount                     = $user.SPNCount
            IsKnownUpnSuffix             = $user.IsKnownUpnSuffix
            IsNonRoutableUpnSuffix       = $user.IsNonRoutableUpnSuffix
            MsDsSupportedEncryptionTypes = $user.MsDsSupportedEncryptionTypes
            EncryptionTypes              = $user.EncryptionTypes
            EncryptionRisk               = $user.EncryptionRisk
            Description                  = [string]$user.Description
        }

        if (-not $enabled) {
            [void]$disabledUsers.Add($row)
        }

        if ($null -ne $lastLogonDays -and $lastLogonDays -gt $InactiveDays) {
            [void]$inactiveUsers.Add($row)
        }
    }

    return [pscustomobject]@{
        DisabledUsers = @($disabledUsers.ToArray() | Sort-Object -Property SamAccountName)
        InactiveUsers = @($inactiveUsers.ToArray() | Sort-Object -Property LastLogonDays -Descending)
    }
}
