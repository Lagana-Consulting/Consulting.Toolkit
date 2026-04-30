function Import-AdAssessmentCsvSafe {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    try {
        return @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    }
    catch {
        return @()
    }
}

function Get-AdAssessmentFirstCsvPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $null }

    foreach ($pattern in $Patterns) {
        $match = @(
            Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object Name |
            Select-Object -First 1
        )
        if ($match.Count -gt 0) {
            return $match[0].FullName
        }
    }

    return $null
}

function Get-AdAssessmentFirstCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    $path = Get-AdAssessmentFirstCsvPath -Directory $Directory -Patterns $Patterns
    return Import-AdAssessmentCsvSafe -Path $path
}

function Test-AdAssessmentBoolean {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }

    $text = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    return $text -match '(?i)^(true|yes|1)$'
}

function ConvertTo-AdAssessmentNumber {
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    $text = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $parsed = 0.0
    if ([double]::TryParse($text, [ref]$parsed)) {
        return $parsed
    }

    return $null
}

function Get-AdAssessmentDomainRiskSummaryData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DomainFolderPath
    )

    if (-not (Test-Path -LiteralPath $DomainFolderPath -PathType Container)) {
        return @()
    }

    $users = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Identity__Users__*.csv')
    $computers = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Identity__ComputersAll__*.csv')
    $passwordPolicy = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Security__PasswordPolicyDefault__*.csv') | Select-Object -First 1
    $privilegedPasswordAge = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Security__PrivilegedPasswordAge__*.csv')
    $adminSdHolder = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Security__AdminSdHolderImpact__*.csv')
    $asrepRoastableUsers = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Security__AsrepRoastableUsers__*.csv')
    $unconstrainedDelegation = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Security__DelegationUnconstrained__*.csv')
    $usersSidHistory = Get-AdAssessmentFirstCsv -Directory $DomainFolderPath -Patterns @('*__Security__UsersSidHistory__*.csv')

    $rows = New-Object System.Collections.Generic.List[object]

    function Add-RiskRow {
        param(
            [string]$Flag,
            [string]$ObjectClass,
            [int]$Count
        )

        if ($Count -le 0) { return }
        $rows.Add([pscustomobject]@{
                Flag        = $Flag
                ObjectClass = $ObjectClass
                Count       = $Count
            })
    }

    $usersStaleCount = @($users | Where-Object {
            $days = ConvertTo-AdAssessmentNumber $_.LastLogonDays
            $null -ne $days -and $days -gt 180
        }).Count
    Add-RiskRow -Flag 'StaleLastLogonOver180d' -ObjectClass 'user' -Count $usersStaleCount

    $computersStaleCount = @($computers | Where-Object {
            $days = ConvertTo-AdAssessmentNumber $_.LastLogonDays
            $null -ne $days -and $days -gt 90
        }).Count
    Add-RiskRow -Flag 'ComputerStaleLastLogonOver90d' -ObjectClass 'computer' -Count $computersStaleCount

    $passwordAgeOver365Count = @($users | Where-Object {
            $age = ConvertTo-AdAssessmentNumber $_.PasswordAgeDays
            $null -ne $age -and $age -gt 365
        }).Count
    Add-RiskRow -Flag 'PasswordAgeOver365d' -ObjectClass 'user' -Count $passwordAgeOver365Count

    $privilegedPasswordAgeOver180Count = @($privilegedPasswordAge | Where-Object {
            $age = ConvertTo-AdAssessmentNumber $_.PasswordAgeDays
            $null -ne $age -and $age -gt 180
        }).Count
    Add-RiskRow -Flag 'PrivilegedPasswordAgeOver180d' -ObjectClass 'user' -Count $privilegedPasswordAgeOver180Count

    $usersNonRoutableUpnCount = @($users | Where-Object { Test-AdAssessmentBoolean $_.IsNonRoutableUpnSuffix }).Count
    Add-RiskRow -Flag 'UPN_NonRoutableSuffix' -ObjectClass 'user' -Count $usersNonRoutableUpnCount

    $usersRc4OnlyCount = @($users | Where-Object {
            $risk = [string]$_.EncryptionRisk
            $types = [string]$_.EncryptionTypes
            $risk -match 'RC4|NoAES|High' -and $types -notmatch 'AES'
        }).Count
    Add-RiskRow -Flag 'Kerberos_NoAES' -ObjectClass 'user' -Count $usersRc4OnlyCount

    $computersRc4OnlyCount = @($computers | Where-Object {
            $risk = [string]$_.EncryptionRisk
            $types = [string]$_.EncryptionTypes
            $risk -match 'RC4|NoAES|High' -and $types -notmatch 'AES'
        }).Count
    Add-RiskRow -Flag 'Kerberos_NoAES' -ObjectClass 'computer' -Count $computersRc4OnlyCount

    $weakPasswordPoliciesCount = 0
    if ($passwordPolicy) {
        $policyWeaknessCount = 0

        if (-not (Test-AdAssessmentBoolean $passwordPolicy.ComplexityEnabled)) { $policyWeaknessCount++ }

        $minLength = ConvertTo-AdAssessmentNumber $passwordPolicy.MinPasswordLength
        if ($null -eq $minLength -or $minLength -lt 12) { $policyWeaknessCount++ }

        $maxAge = ConvertTo-AdAssessmentNumber $passwordPolicy.MaxPasswordAgeDays
        if ($null -eq $maxAge -or $maxAge -eq 0 -or $maxAge -gt 90) { $policyWeaknessCount++ }

        $lockoutThreshold = ConvertTo-AdAssessmentNumber $passwordPolicy.LockoutThreshold
        if ($null -eq $lockoutThreshold -or $lockoutThreshold -le 0) { $policyWeaknessCount++ }

        if (Test-AdAssessmentBoolean $passwordPolicy.ReversibleEncryptionEnabled) { $policyWeaknessCount++ }

        if ($policyWeaknessCount -gt 0) { $weakPasswordPoliciesCount = 1 }
    }
    Add-RiskRow -Flag 'WeakPasswordPolicy' -ObjectClass 'domain' -Count $weakPasswordPoliciesCount

    $usersSidHistoryCount = @($users | Where-Object {
            $count = ConvertTo-AdAssessmentNumber $_.SidHistoryCount
            $null -ne $count -and $count -gt 0
        }).Count
    if ($usersSidHistoryCount -eq 0) { $usersSidHistoryCount = @($usersSidHistory).Count }
    Add-RiskRow -Flag 'SIDHistoryPresent' -ObjectClass 'user' -Count $usersSidHistoryCount

    foreach ($group in @($adminSdHolder | Group-Object -Property ObjectClass)) {
        $objectClass = if ([string]::IsNullOrWhiteSpace($group.Name)) { 'object' } else { [string]$group.Name }
        Add-RiskRow -Flag 'AdminSDHolderProtected' -ObjectClass $objectClass -Count $group.Count
    }

    foreach ($group in @($unconstrainedDelegation | Group-Object -Property ObjectClass)) {
        $objectClass = if ([string]::IsNullOrWhiteSpace($group.Name)) { 'object' } else { [string]$group.Name }
        Add-RiskRow -Flag 'UnconstrainedDelegation' -ObjectClass $objectClass -Count $group.Count
    }

    Add-RiskRow -Flag 'AsrepRoastableUsers' -ObjectClass 'user' -Count @($asrepRoastableUsers).Count

    return @(
        $rows.ToArray() |
        Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, Flag, ObjectClass
    )
}

function Get-AdAssessmentForestRiskSummaryData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DiscoveryOutputPath
    )

    $domainsRoot = Join-Path $DiscoveryOutputPath '20_domains'
    if (-not (Test-Path -LiteralPath $domainsRoot -PathType Container)) { return @() }

    $allRows = foreach ($domainDir in @(Get-ChildItem -LiteralPath $domainsRoot -Directory -Filter 'Domain-*' -ErrorAction SilentlyContinue)) {
        Get-AdAssessmentDomainRiskSummaryData -DomainFolderPath $domainDir.FullName
    }

    return @(
        $allRows |
        Group-Object -Property Flag, ObjectClass |
        ForEach-Object {
            $parts = $_.Name -split ', '
            [pscustomobject]@{
                Flag        = $parts[0]
                ObjectClass = $parts[1]
                Count       = @($_.Group | Measure-Object -Property Count -Sum).Sum
            }
        } |
        Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, Flag, ObjectClass
    )
}
