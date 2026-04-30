function New-AdMigrationIncludeFile {
    <#
    .SYNOPSIS
    Build default migration include files from discovery output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot,

        [ValidateSet('All', 'Users', 'Groups', 'Computers')]
        [string]$ObjectType = 'All',

        [string]$OutputPath,

        [string]$PlanningConfigPath,

        [switch]$IncludeNonRoutableUpnUsers
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $rules = Resolve-AdPlanningRules -PlanningConfigPath $PlanningConfigPath
    $runData = Get-AdPlanningRunData -RunRoot $RunRoot

    $excludedUserNames = @($rules.ExcludedUserSamAccountNames | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    $privilegedUsers = @($runData.PrivilegedAccounts | ForEach-Object { ([string]$_.SamAccountName).Trim().ToLowerInvariant() } | Sort-Object -Unique)
    $serviceAccounts = @($runData.ServiceAccounts | ForEach-Object { ([string]$_.SamAccountName).Trim().ToLowerInvariant() } | Sort-Object -Unique)

    $rows = New-Object System.Collections.Generic.List[object]

    if ($ObjectType -in @('All', 'Users')) {
        foreach ($user in @($runData.Users)) {
            $sam = ([string]$user.SamAccountName).Trim().ToLowerInvariant()
            $lastLogonDays = if ([string]::IsNullOrWhiteSpace([string]$user.LastLogonDays)) { $null } else { ConvertTo-AdPlanningInt -Value $user.LastLogonDays -Default 0 }
            $isNonRoutableUpn = Test-AdPlanningBoolean $user.IsNonRoutableUpnSuffix
            if (-not (Test-AdPlanningBoolean $user.Enabled)) { continue }
            if ($sam -in $excludedUserNames) { continue }
            if ($isNonRoutableUpn -and $IncludeNonRoutableUpnUsers) {
                [void]$rows.Add([pscustomobject]@{
                    ObjectClass       = 'User'
                    DomainFqdn        = [string]$user.DomainFqdn
                    SamAccountName    = [string]$user.SamAccountName
                    Name              = [string]$user.Name
                    DistinguishedName = [string]$user.DistinguishedName
                    UserPrincipalName = [string]$user.UserPrincipalName
                    Enabled           = [string]$user.Enabled
                    LastLogonDays     = [string]$user.LastLogonDays
                    IncludeReason     = 'Enabled user candidate included with non-routable UPN override'
                })
                continue
            }
            if ($sam -in $privilegedUsers) { continue }
            if ($sam -in $serviceAccounts) { continue }
            if ($null -ne $lastLogonDays -and $lastLogonDays -gt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.UserStaleDays -Default 180)) { continue }
            if ($isNonRoutableUpn) { continue }

            [void]$rows.Add([pscustomobject]@{
                ObjectClass       = 'User'
                DomainFqdn        = [string]$user.DomainFqdn
                SamAccountName    = [string]$user.SamAccountName
                Name              = [string]$user.Name
                DistinguishedName = [string]$user.DistinguishedName
                UserPrincipalName = [string]$user.UserPrincipalName
                Enabled           = [string]$user.Enabled
                LastLogonDays     = [string]$user.LastLogonDays
                IncludeReason     = 'Enabled standard user candidate'
            })
        }
    }

    if ($ObjectType -in @('All', 'Groups')) {
        foreach ($group in @($runData.Groups)) {
            if (Test-AdPlanningBuiltInGroup -Group $group -Rules $rules) { continue }

            [void]$rows.Add([pscustomobject]@{
                ObjectClass       = 'Group'
                DomainFqdn        = [string]$group.DomainFqdn
                SamAccountName    = [string]$group.SamAccountName
                Name              = [string]$group.Name
                DistinguishedName = [string]$group.DistinguishedName
                GroupCategory     = [string]$group.GroupCategory
                GroupScope        = [string]$group.GroupScope
                IncludeReason     = 'Group is not marked as built-in'
            })
        }
    }

    if ($ObjectType -in @('All', 'Computers')) {
        foreach ($computer in @($runData.Computers)) {
            $lastLogonDays = if ([string]::IsNullOrWhiteSpace([string]$computer.LastLogonDays)) { $null } else { ConvertTo-AdPlanningInt -Value $computer.LastLogonDays -Default 0 }
            if (-not (Test-AdPlanningBoolean $computer.Enabled)) { continue }
            if ($null -ne $lastLogonDays -and $lastLogonDays -gt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.ComputerStaleDays -Default 90)) { continue }

            [void]$rows.Add([pscustomobject]@{
                ObjectClass       = if (Test-AdPlanningBoolean $computer.IsServer) { 'Server' } else { 'Workstation' }
                DomainFqdn        = [string]$computer.DomainFqdn
                SamAccountName    = [string]$computer.SamAccountName
                Name              = [string]$computer.Name
                DistinguishedName = [string]$computer.DistinguishedName
                DnsHostName       = [string]$computer.DnsHostName
                OperatingSystem   = [string]$computer.OperatingSystem
                Enabled           = [string]$computer.Enabled
                LastLogonDays     = [string]$computer.LastLogonDays
                IncludeReason     = 'Enabled active computer candidate'
            })
        }
    }

    $result = $rows.ToArray()
    if ($OutputPath) {
        $directory = Split-Path -Parent $OutputPath
        if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $result | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8 -Force
    }

    return [pscustomobject]@{
        OutputPath = $OutputPath
        Rows       = $result
        Count      = $result.Count
        ObjectType = $ObjectType
        IncludeNonRoutableUpnUsers = [bool]$IncludeNonRoutableUpnUsers
    }
}
