function New-AdMigrationExcludeFile {
    <#
    .SYNOPSIS
    Build default migration exclude and review candidate file from discovery output.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot,

        [string]$OutputPath,

        [string]$PlanningConfigPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $rules = Resolve-AdPlanningRules -PlanningConfigPath $PlanningConfigPath
    $runData = Get-AdPlanningRunData -RunRoot $RunRoot

    $rows = New-Object System.Collections.Generic.List[object]
    $excludedUserNames = @($rules.ExcludedUserSamAccountNames | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    $privilegedUsers = @($runData.PrivilegedAccounts | ForEach-Object { ([string]$_.SamAccountName).Trim().ToLowerInvariant() } | Sort-Object -Unique)
    $serviceAccounts = @($runData.ServiceAccounts | ForEach-Object { ([string]$_.SamAccountName).Trim().ToLowerInvariant() } | Sort-Object -Unique)
    $groupReviewSignals = Get-AdPlanningGroupReviewSignals -RunRoot $RunRoot

    foreach ($user in @($runData.Users)) {
        $sam = ([string]$user.SamAccountName).Trim().ToLowerInvariant()
        $lastLogonDays = if ([string]::IsNullOrWhiteSpace([string]$user.LastLogonDays)) { $null } else { ConvertTo-AdPlanningInt -Value $user.LastLogonDays -Default 0 }

        if (-not (Test-AdPlanningBoolean $user.Enabled)) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = 'User'; DomainFqdn = [string]$user.DomainFqdn; SamAccountName = [string]$user.SamAccountName; Name = [string]$user.Name; DistinguishedName = [string]$user.DistinguishedName; Reason = 'DisabledUser'; Recommendation = 'Exclude from default migration scope unless explicitly requested.'; LastLogonDays = [string]$user.LastLogonDays
            })
            continue
        }
        if ($sam -in $excludedUserNames) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = 'User'; DomainFqdn = [string]$user.DomainFqdn; SamAccountName = [string]$user.SamAccountName; Name = [string]$user.Name; DistinguishedName = [string]$user.DistinguishedName; Reason = 'BuiltInOrDefaultAccount'; Recommendation = 'Keep out of standard migration waves and review separately.'; LastLogonDays = [string]$user.LastLogonDays
            })
            continue
        }
        if ($sam -in $privilegedUsers) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = 'User'; DomainFqdn = [string]$user.DomainFqdn; SamAccountName = [string]$user.SamAccountName; Name = [string]$user.Name; DistinguishedName = [string]$user.DistinguishedName; Reason = 'PrivilegedAccount'; Recommendation = 'Move to a dedicated privileged-account wave.'; LastLogonDays = [string]$user.LastLogonDays
            })
            continue
        }
        if ($sam -in $serviceAccounts) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = 'User'; DomainFqdn = [string]$user.DomainFqdn; SamAccountName = [string]$user.SamAccountName; Name = [string]$user.Name; DistinguishedName = [string]$user.DistinguishedName; Reason = 'ServiceAccountCandidate'; Recommendation = 'Review with application owners before migration.'; LastLogonDays = [string]$user.LastLogonDays
            })
            continue
        }
        if ($null -ne $lastLogonDays -and $lastLogonDays -gt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.UserStaleDays -Default 180)) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = 'User'; DomainFqdn = [string]$user.DomainFqdn; SamAccountName = [string]$user.SamAccountName; Name = [string]$user.Name; DistinguishedName = [string]$user.DistinguishedName; Reason = 'StaleUser'; Recommendation = 'Exclude from standard waves until ownership and lifecycle are confirmed.'; LastLogonDays = [string]$user.LastLogonDays
            })
            continue
        }
    }

    foreach ($group in @($runData.Groups)) {
        if (Test-AdPlanningBuiltInGroup -Group $group -Rules $rules) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = 'Group'; DomainFqdn = [string]$group.DomainFqdn; SamAccountName = [string]$group.SamAccountName; Name = [string]$group.Name; DistinguishedName = [string]$group.DistinguishedName; Reason = 'BuiltInGroup'; Recommendation = 'Exclude built-in groups from standard migration scope.'; LastLogonDays = ''
            })
            continue
        }

        $groupKey = New-AdPlanningGroupKey -Group $group
        if (-not [string]::IsNullOrWhiteSpace($groupKey) -and $groupReviewSignals.ContainsKey($groupKey)) {
            $reasons = @($groupReviewSignals[$groupKey].ToArray() | Sort-Object)
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = 'Group'; DomainFqdn = [string]$group.DomainFqdn; SamAccountName = [string]$group.SamAccountName; Name = [string]$group.Name; DistinguishedName = [string]$group.DistinguishedName; Reason = ($reasons -join ';'); Recommendation = 'Exclude from default group include scope and review group membership or lifecycle before migration.'; LastLogonDays = ''
            })
        }
    }

    foreach ($computer in @($runData.Computers)) {
        $lastLogonDays = if ([string]::IsNullOrWhiteSpace([string]$computer.LastLogonDays)) { $null } else { ConvertTo-AdPlanningInt -Value $computer.LastLogonDays -Default 0 }
        if (-not (Test-AdPlanningBoolean $computer.Enabled)) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = if (Test-AdPlanningBoolean $computer.IsServer) { 'Server' } else { 'Workstation' }; DomainFqdn = [string]$computer.DomainFqdn; SamAccountName = [string]$computer.SamAccountName; Name = [string]$computer.Name; DistinguishedName = [string]$computer.DistinguishedName; Reason = 'DisabledComputer'; Recommendation = 'Exclude from migration scope unless device is returning to service.'; LastLogonDays = [string]$computer.LastLogonDays
            })
            continue
        }
        if ($null -ne $lastLogonDays -and $lastLogonDays -gt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.ComputerStaleDays -Default 90)) {
            [void]$rows.Add([pscustomobject]@{
                ObjectClass = if (Test-AdPlanningBoolean $computer.IsServer) { 'Server' } else { 'Workstation' }; DomainFqdn = [string]$computer.DomainFqdn; SamAccountName = [string]$computer.SamAccountName; Name = [string]$computer.Name; DistinguishedName = [string]$computer.DistinguishedName; Reason = 'StaleComputer'; Recommendation = 'Exclude stale device objects from default waves until validated.'; LastLogonDays = [string]$computer.LastLogonDays
            })
        }
    }

    $result = @($rows.ToArray() | Sort-Object ObjectClass, Reason, SamAccountName)
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
    }
}
