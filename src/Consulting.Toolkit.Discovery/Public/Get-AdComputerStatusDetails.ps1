function Get-AdComputerStatusDetails {
    <#
    .SYNOPSIS
    Splits discovered computer rows into inactive workstation and inactive server datasets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Computers,

        [int]$InactiveDays = 90
    )

    $inactiveWorkstations = New-Object System.Collections.Generic.List[object]
    $inactiveServers = New-Object System.Collections.Generic.List[object]

    foreach ($computer in @($Computers)) {
        $lastLogonDays = ConvertTo-AdComputerStatusNullableInt -Value $computer.LastLogonDays
        if ($null -eq $lastLogonDays -or $lastLogonDays -le $InactiveDays) {
            continue
        }

        $isServer = ConvertTo-AdComputerStatusBoolean -Value $computer.IsServer -Default $false
        $row = [pscustomobject]@{
            DomainFqdn                   = [string]$computer.DomainFqdn
            Name                         = [string]$computer.Name
            SamAccountName               = [string]$computer.SamAccountName
            DistinguishedName            = [string]$computer.DistinguishedName
            Enabled                      = ConvertTo-AdComputerStatusBoolean -Value $computer.Enabled -Default $true
            DnsHostName                  = [string]$computer.DnsHostName
            OperatingSystem              = [string]$computer.OperatingSystem
            OperatingSystemVersion       = [string]$computer.OperatingSystemVersion
            IsServer                     = [bool]$isServer
            WhenCreated                  = $computer.WhenCreated
            WhenChanged                  = $computer.WhenChanged
            LastLogonTimestampUtc        = $computer.LastLogonTimestampUtc
            LastLogonDays                = [string]$lastLogonDays
            InactiveThresholdDays        = $InactiveDays
            SPNCount                     = $computer.SPNCount
            MsDsSupportedEncryptionTypes = $computer.MsDsSupportedEncryptionTypes
            EncryptionTypes              = $computer.EncryptionTypes
            EncryptionRisk               = $computer.EncryptionRisk
            Description                  = [string]$computer.Description
        }

        if ($isServer) {
            [void]$inactiveServers.Add($row)
        }
        else {
            [void]$inactiveWorkstations.Add($row)
        }
    }

    return [pscustomobject]@{
        InactiveWorkstations = @($inactiveWorkstations.ToArray() | Sort-Object -Property LastLogonDays -Descending)
        InactiveServers      = @($inactiveServers.ToArray() | Sort-Object -Property LastLogonDays -Descending)
    }
}
