function New-AdMigrationLabSeed {
    <#
    .SYNOPSIS
    Seed a lab AD domain with OU, user, and group objects from discovery output.

    .DESCRIPTION
    Imports user and group discovery CSVs from a discovery run root and recreates
    the source OU/container path under a lab staging OU. The command creates
    groups first, then users. It is designed for lab testing and supports -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot,

        [string]$StagingOuName = 'Migration Lab Staging',

        [string]$StagingBaseDn,

        [int]$UserLimit = 0,

        [int]$GroupLimit = 0,

        [switch]$PreserveSourceOuPath = $true,

        [switch]$IncludeBuiltInGroups,

        [switch]$IncludeBuiltInUsers,

        [switch]$CreateDisabledUsers,

        [string]$DefaultPassword = 'P@ssw0rd!12345',

        [string]$UserPrincipalNameSuffix,

        [switch]$PlanOnly,

        [switch]$StopOnError,

        [string]$OutputPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not $PlanOnly) {
        Import-Module ActiveDirectory -ErrorAction Stop
    }

    if ([string]::IsNullOrWhiteSpace($StagingBaseDn)) {
        $StagingBaseDn = if ($PlanOnly) { 'DC=lab,DC=local' } else { Get-AdTestingDomainDn }
    }

    $data = Get-AdTestingDiscoveryData -RunRoot $RunRoot
    $stagingRootDn = Ensure-AdTestingOu -Name $StagingOuName -ParentDn $StagingBaseDn -Description 'Migration lab staging root generated from discovery output' -SkipDirectoryLookup:$PlanOnly -WhatIf:$WhatIfPreference
    $actions = New-Object System.Collections.Generic.List[object]

    $builtInGroupNames = @(
        'administrators',
        'authenticated users',
        'cert publishers',
        'denied rodc password replication group',
        'dnsadmins',
        'dnsupdateproxy',
        'domain admins',
        'domain computers',
        'domain controllers',
        'domain guests',
        'domain users',
        'enterprise admins',
        'enterprise key admins',
        'enterprise read-only domain controllers',
        'group policy creator owners',
        'guests',
        'key admins',
        'krbtgt',
        'pre-windows 2000 compatible access',
        'protected users',
        'read-only domain controllers',
        'schema admins',
        'users'
    )

    $groups = @($data.Groups | Where-Object {
        if ([string]::IsNullOrWhiteSpace([string]$_.SamAccountName)) {
            $false
        }
        elseif ($IncludeBuiltInGroups) {
            $true
        }
        else {
            $sam = ([string]$_.SamAccountName).Trim().ToLowerInvariant()
            $dn = [string]$_.DistinguishedName
            ($builtInGroupNames -notcontains $sam) -and ($dn -notmatch '^(?i)CN=[^,]+,CN=(Builtin|Users),')
        }
    })
    if ($GroupLimit -gt 0) {
        $groups = @($groups | Select-Object -First $GroupLimit)
    }

    foreach ($group in $groups) {
        $name = ConvertTo-AdTestingSafeName -Value ([string]$group.Name) -Fallback ([string]$group.SamAccountName) -MaxLength 64
        $sam = Get-AdTestingUniqueSam -SamAccountName ([string]$group.SamAccountName) -ObjectType Group
        $path = Resolve-AdTestingObjectPath -Row $group -StagingBaseDn $stagingRootDn -PreserveSourceOuPath:$PreserveSourceOuPath -SkipDirectoryLookup:$PlanOnly -WhatIf:$WhatIfPreference
        $escapedSam = ConvertTo-AdTestingLdapFilterValue -Value $sam
        $existing = if ($PlanOnly) { $null } else { Get-ADGroup -LDAPFilter "(sAMAccountName=$escapedSam)" -ErrorAction SilentlyContinue | Select-Object -First 1 }

        if ($existing) {
            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'Group' -Name $name -SamAccountName $sam -Action 'Skipped' -Path $path -DistinguishedName $existing.DistinguishedName -SourceDistinguishedName ([string]$group.DistinguishedName) -Message 'Group already exists'))
            continue
        }

        $scope = if ([string]::IsNullOrWhiteSpace([string]$group.GroupScope)) { 'Global' } else { [string]$group.GroupScope }
        $category = if ([string]::IsNullOrWhiteSpace([string]$group.GroupCategory)) { 'Security' } else { [string]$group.GroupCategory }

        if ($PlanOnly) {
            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'Group' -Name $name -SamAccountName $sam -Action 'Planned' -Path $path -SourceDistinguishedName ([string]$group.DistinguishedName) -Message 'Planned from discovery group row'))
            continue
        }

        try {
            if ($PSCmdlet.ShouldProcess($sam, "Create AD group in $path")) {
                $newGroupParams = @{
                    Name          = $name
                    SamAccountName = $sam
                    GroupScope    = $scope
                    GroupCategory = $category
                    Path          = $path
                    ErrorAction   = 'Stop'
                }
                $description = ConvertTo-AdTestingSafeDescription -Value ([string]$group.Description)
                if ($description) {
                    $newGroupParams.Description = $description
                }

                New-ADGroup @newGroupParams
            }

            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'Group' -Name $name -SamAccountName $sam -Action 'Created' -Path $path -SourceDistinguishedName ([string]$group.DistinguishedName) -Message 'Created from discovery group row'))
        }
        catch {
            $message = $_.Exception.Message
            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'Group' -Name $name -SamAccountName $sam -Action 'Failed' -Path $path -SourceDistinguishedName ([string]$group.DistinguishedName) -Message $message))
            Write-Warning "Failed to create group '$sam': $message"
            if ($StopOnError) { throw }
        }
    }

    $builtInUserNames = @(
        'administrator',
        'defaultaccount',
        'guest',
        'krbtgt',
        'wdagutilityaccount'
    )

    $users = @($data.Users | Where-Object {
        if ([string]::IsNullOrWhiteSpace([string]$_.SamAccountName)) {
            $false
        }
        elseif ($IncludeBuiltInUsers) {
            $true
        }
        else {
            $sam = ([string]$_.SamAccountName).Trim().ToLowerInvariant()
            $builtInUserNames -notcontains $sam
        }
    })
    if ($UserLimit -gt 0) {
        $users = @($users | Select-Object -First $UserLimit)
    }

    $securePassword = ConvertTo-SecureString -String $DefaultPassword -AsPlainText -Force
    foreach ($user in $users) {
        $name = ConvertTo-AdTestingSafeName -Value ([string]$user.Name) -Fallback ([string]$user.SamAccountName) -MaxLength 64
        $sam = Get-AdTestingUniqueSam -SamAccountName ([string]$user.SamAccountName) -ObjectType User
        $path = Resolve-AdTestingObjectPath -Row $user -StagingBaseDn $stagingRootDn -PreserveSourceOuPath:$PreserveSourceOuPath -SkipDirectoryLookup:$PlanOnly -WhatIf:$WhatIfPreference
        $escapedSam = ConvertTo-AdTestingLdapFilterValue -Value $sam
        $existing = if ($PlanOnly) { $null } else { Get-ADUser -LDAPFilter "(sAMAccountName=$escapedSam)" -ErrorAction SilentlyContinue | Select-Object -First 1 }

        if ($existing) {
            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'User' -Name $name -SamAccountName $sam -Action 'Skipped' -Path $path -DistinguishedName $existing.DistinguishedName -SourceDistinguishedName ([string]$user.DistinguishedName) -Message 'User already exists'))
            continue
        }

        $enabled = if ($CreateDisabledUsers) { $false } else { ConvertTo-AdTestingBoolean -Value $user.Enabled -Default $true }
        $upnSuffix = if (-not [string]::IsNullOrWhiteSpace($UserPrincipalNameSuffix)) {
            $UserPrincipalNameSuffix
        }
        elseif ($PlanOnly) {
            'lab.local'
        }
        else {
            (Get-ADDomain).DNSRoot
        }
        $upn = "$sam@$upnSuffix"

        if ($PlanOnly) {
            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'User' -Name $name -SamAccountName $sam -Action 'Planned' -Path $path -SourceDistinguishedName ([string]$user.DistinguishedName) -Message "Planned from discovery user row; Enabled=$enabled; UPN=$upn"))
            continue
        }

        try {
            if ($PSCmdlet.ShouldProcess($sam, "Create AD user in $path")) {
                $newUserParams = @{
                    Name                  = $name
                    SamAccountName        = $sam
                    UserPrincipalName     = $upn
                    DisplayName           = $name
                    Path                  = $path
                    AccountPassword       = $securePassword
                    Enabled               = $enabled
                    ChangePasswordAtLogon = $false
                    ErrorAction           = 'Stop'
                }
                $description = ConvertTo-AdTestingSafeDescription -Value ([string]$user.Description)
                if ($description) {
                    $newUserParams.Description = $description
                }

                New-ADUser @newUserParams
            }

            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'User' -Name $name -SamAccountName $sam -Action 'Created' -Path $path -SourceDistinguishedName ([string]$user.DistinguishedName) -Message "Created from discovery user row; Enabled=$enabled"))
        }
        catch {
            $message = $_.Exception.Message
            [void]$actions.Add((New-AdTestingActionRow -ObjectType 'User' -Name $name -SamAccountName $sam -Action 'Failed' -Path $path -SourceDistinguishedName ([string]$user.DistinguishedName) -Message $message))
            Write-Warning "Failed to create user '$sam': $message"
            if ($StopOnError) { throw }
        }
    }

    $rows = $actions.ToArray()
    if ($OutputPath) {
        $directory = Split-Path -Parent $OutputPath
        if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8 -Force
    }

    return [pscustomobject]@{
        RunRoot       = $RunRoot
        StagingRootDn = $stagingRootDn
        OutputPath    = $OutputPath
        GroupsSeen    = @($data.Groups).Count
        UsersSeen     = @($data.Users).Count
        GroupsInScope = @($groups).Count
        UsersInScope  = @($users).Count
        GroupsCreated = @($rows | Where-Object { $_.ObjectType -eq 'Group' -and $_.Action -eq 'Created' }).Count
        UsersCreated  = @($rows | Where-Object { $_.ObjectType -eq 'User' -and $_.Action -eq 'Created' }).Count
        Planned       = @($rows | Where-Object { $_.Action -eq 'Planned' }).Count
        Skipped       = @($rows | Where-Object { $_.Action -eq 'Skipped' }).Count
        Failed        = @($rows | Where-Object { $_.Action -eq 'Failed' }).Count
        Actions       = $rows
    }
}
