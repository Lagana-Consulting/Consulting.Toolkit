function Get-AdTimestamp {
    [CmdletBinding()]
    param(
        [ValidateSet('File', 'Display', 'Iso')]
        [string]$Format = 'File'
    )

    switch ($Format) {
        'Display' { return (Get-Date).ToString('M/d/yyyy h:mm:ss tt') }
        'Iso' { return (Get-Date).ToString('o') }
        default { return (Get-Date).ToString('yyyyMMdd-HHmmss') }
    }
}

function Import-AdAnalysisCsvSafe {
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    try {
        return @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    } catch {
        return @()
    }
}

function Get-AdDiscoveryIndexData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot
    )

    foreach ($relativePath in @(
            '99_manifest\Discovery.Index.json',
            '99_manifest\Discovery__Index__Run.json'
        )) {
        $path = Join-Path $RunRoot $relativePath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try {
                return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            } catch {
                return $null
            }
        }
    }

    return $null
}

function Get-AdDiscoveryDomainFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot
    )

    $domainsRoot = Join-Path $RunRoot '20_domains'
    if (-not (Test-Path -LiteralPath $domainsRoot -PathType Container)) { return @() }

    return @(
        Get-ChildItem -LiteralPath $domainsRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Domain-' } |
        Sort-Object Name
    )
}

function Get-AdDiscoveryFirstCsvPath {
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

function Get-AdDiscoveryFirstCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string[]]$Patterns
    )

    $path = Get-AdDiscoveryFirstCsvPath -Directory $Directory -Patterns $Patterns
    return Import-AdAnalysisCsvSafe -Path $path
}

function Test-AdAnalysisBoolean {
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

function ConvertTo-AdAnalysisNumber {
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

function New-AdDiscoveryRiskRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Flag,

        [Parameter(Mandatory)]
        [ValidateSet('Critical', 'High', 'Medium', 'Low')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [int]$Count,

        [string]$Description,
        [string]$Recommendation
    )

    if ($Count -le 0) { return $null }

    return [pscustomobject]@{
        Flag           = $Flag
        Severity       = $Severity
        Count          = $Count
        Description    = $Description
        Recommendation = $Recommendation
    }
}

function Get-AdDiscoveryRunSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot
    )

    if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
        throw "Run root not found: $RunRoot"
    }

    $index = Get-AdDiscoveryIndexData -RunRoot $RunRoot
    $forestSummary = Import-AdAnalysisCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Summary__Forest.csv') | Select-Object -First 1
    $trusts = Import-AdAnalysisCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Security__Trusts__Forest.csv')
    $upnSuffixes = Import-AdAnalysisCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Identity__UpnSuffixes__Forest.csv')
    $sites = Import-AdAnalysisCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Network__Sites__Forest.csv')
    $siteLinks = Import-AdAnalysisCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Network__SiteLinks__Forest.csv')
    $adcsEnterpriseCas = Import-AdAnalysisCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Security__ADCS__EnterpriseCAs__Forest.csv')

    $domainFolders = Get-AdDiscoveryDomainFolders -RunRoot $RunRoot
    $domainSummaries = @()

    $allUsers = @()
    $allGroups = @()
    $allComputers = @()
    $allSpns = @()
    $allPrivilegedAccounts = @()
    $allPrivilegedPasswordAge = @()
    $allAdminSdHolder = @()
    $allAsrepRoastableUsers = @()
    $allUnconstrainedDelegation = @()
    $allProtectedUsers = @()
    $allPasswordPolicies = @()
    $allServiceAccountCandidates = @()
    $allUsersSidHistory = @()
    $allDomainControllers = @()
    $allGpos = @()
    $allOus = @()

    foreach ($folder in $domainFolders) {
        $domainName = $folder.Name -replace '^Domain-', ''

        $users = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__Users__*.csv')
        $groups = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__Groups__*.csv')
        $computers = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__ComputersAll__*.csv')
        $spns = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__Spns__*.csv', '*__Identity__SPNs__*.csv')
        $domainControllers = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Infrastructure__DomainControllers__*.csv')
        $ous = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Structure__OrganizationalUnits__*.csv')
        $gpos = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__GPO__Inventory__*.csv')
        $passwordPolicy = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__PasswordPolicyDefault__*.csv') | Select-Object -First 1
        $fgppPolicies = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__PasswordPolicyFgpp__*.csv')
        $serviceAccountCandidates = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__ServiceAccountCandidates__*.csv')
        $privilegedAccounts = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__PrivilegedAccounts__*.csv')
        $privilegedPasswordAge = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__PrivilegedPasswordAge__*.csv')
        $adminSdHolder = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__AdminSdHolderImpact__*.csv')
        $asrepRoastableUsers = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__AsrepRoastableUsers__*.csv')
        $unconstrainedDelegation = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__DelegationUnconstrained__*.csv')
        $protectedUsers = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__ProtectedUsers__*.csv')
        $usersSidHistory = Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__UsersSidHistory__*.csv')

        $allUsers += $users
        $allGroups += $groups
        $allComputers += $computers
        $allSpns += $spns
        $allPrivilegedAccounts += $privilegedAccounts
        $allPrivilegedPasswordAge += $privilegedPasswordAge
        $allAdminSdHolder += $adminSdHolder
        $allAsrepRoastableUsers += $asrepRoastableUsers
        $allUnconstrainedDelegation += $unconstrainedDelegation
        $allProtectedUsers += $protectedUsers
        if ($passwordPolicy) { $allPasswordPolicies += $passwordPolicy }
        $allServiceAccountCandidates += $serviceAccountCandidates
        $allUsersSidHistory += $usersSidHistory
        $allDomainControllers += $domainControllers
        $allGpos += $gpos
        $allOus += $ous

        $usersTotal = @($users).Count
        $groupsTotal = @($groups).Count
        $computersTotal = @($computers).Count
        $serversTotal = @($computers | Where-Object { Test-AdAnalysisBoolean $_.IsServer }).Count
        $workstationsTotal = $computersTotal - $serversTotal

        $usersStaleCount = @($users | Where-Object {
                $days = ConvertTo-AdAnalysisNumber $_.LastLogonDays
                $null -ne $days -and $days -gt 180
            }).Count
        $computersStaleCount = @($computers | Where-Object {
                $days = ConvertTo-AdAnalysisNumber $_.LastLogonDays
                $null -ne $days -and $days -gt 90
            }).Count

        $disabledUsersCount = @($users | Where-Object { -not (Test-AdAnalysisBoolean $_.Enabled) }).Count
        $disabledComputersCount = @($computers | Where-Object { -not (Test-AdAnalysisBoolean $_.Enabled) }).Count
        $usersNonRoutableUpnCount = @($users | Where-Object { Test-AdAnalysisBoolean $_.IsNonRoutableUpnSuffix }).Count

        $usersSidHistoryCount = @($users | Where-Object {
                $count = ConvertTo-AdAnalysisNumber $_.SidHistoryCount
                $null -ne $count -and $count -gt 0
            }).Count
        if ($usersSidHistoryCount -eq 0) { $usersSidHistoryCount = @($usersSidHistory).Count }

        $weakPasswordPoliciesCount = 0
        if ($passwordPolicy) {
            $policyWeaknessCount = 0

            if (-not (Test-AdAnalysisBoolean $passwordPolicy.ComplexityEnabled)) { $policyWeaknessCount++ }

            $minLength = ConvertTo-AdAnalysisNumber $passwordPolicy.MinPasswordLength
            if ($null -eq $minLength -or $minLength -lt 12) { $policyWeaknessCount++ }

            $maxAge = ConvertTo-AdAnalysisNumber $passwordPolicy.MaxPasswordAgeDays
            if ($null -eq $maxAge -or $maxAge -eq 0 -or $maxAge -gt 90) { $policyWeaknessCount++ }

            $lockoutThreshold = ConvertTo-AdAnalysisNumber $passwordPolicy.LockoutThreshold
            if ($null -eq $lockoutThreshold -or $lockoutThreshold -le 0) { $policyWeaknessCount++ }

            if (Test-AdAnalysisBoolean $passwordPolicy.ReversibleEncryptionEnabled) { $policyWeaknessCount++ }

            if ($policyWeaknessCount -gt 0) { $weakPasswordPoliciesCount = 1 }
        }

        $usersStalePct = if ($usersTotal -gt 0) { [math]::Round(($usersStaleCount / $usersTotal) * 100, 1) } else { 0 }
        $computersStalePct = if ($computersTotal -gt 0) { [math]::Round(($computersStaleCount / $computersTotal) * 100, 1) } else { 0 }

        $domainSummaries += [pscustomobject]@{
            Domain  = $domainName
            Summary = [pscustomobject]@{
                UsersTotal                    = $usersTotal
                GroupsTotal                   = $groupsTotal
                ComputersTotal                = $computersTotal
                WorkstationsTotal             = $workstationsTotal
                ServersTotal                  = $serversTotal
                SpnCount                      = @($spns).Count
                OuCount                       = @($ous).Count
                GpoCount                      = @($gpos).Count
                DomainControllerCount         = @($domainControllers).Count
                ServiceAccountCandidatesCount = @($serviceAccountCandidates).Count
                PrivilegedAccountsCount       = @($privilegedAccounts).Count
                UsersStaleCount               = $usersStaleCount
                UsersStalePct                 = $usersStalePct
                ComputersStaleCount           = $computersStaleCount
                ComputersStalePct             = $computersStalePct
                DisabledUsersCount            = $disabledUsersCount
                DisabledComputersCount        = $disabledComputersCount
                UsersNonRoutableUPNCount      = $usersNonRoutableUpnCount
                UsersSidHistoryCount          = $usersSidHistoryCount
                AdminSdHolderImpactCount      = @($adminSdHolder).Count
                AsrepRoastableUsersCount      = @($asrepRoastableUsers).Count
                UnconstrainedDelegationCount  = @($unconstrainedDelegation).Count
                ProtectedUsersCount           = @($protectedUsers).Count
                WeakPasswordPoliciesCount     = $weakPasswordPoliciesCount
                FGPPCount                     = @($fgppPolicies).Count
                PasswordPolicy                = $passwordPolicy
            }
        }
    }

    $usersTotal = @($allUsers).Count
    $groupsTotal = @($allGroups).Count
    $computersTotal = @($allComputers).Count
    $serversTotal = @($allComputers | Where-Object { Test-AdAnalysisBoolean $_.IsServer }).Count
    $workstationsTotal = $computersTotal - $serversTotal

    $usersStaleCount = @($allUsers | Where-Object {
            $days = ConvertTo-AdAnalysisNumber $_.LastLogonDays
            $null -ne $days -and $days -gt 180
        }).Count
    $computersStaleCount = @($allComputers | Where-Object {
            $days = ConvertTo-AdAnalysisNumber $_.LastLogonDays
            $null -ne $days -and $days -gt 90
        }).Count

    $disabledUsersCount = @($allUsers | Where-Object { -not (Test-AdAnalysisBoolean $_.Enabled) }).Count
    $disabledComputersCount = @($allComputers | Where-Object { -not (Test-AdAnalysisBoolean $_.Enabled) }).Count

    $usersNonRoutableUPNCount = @($allUsers | Where-Object { Test-AdAnalysisBoolean $_.IsNonRoutableUpnSuffix }).Count
    $usersSidHistoryCount = @($allUsers | Where-Object {
            $count = ConvertTo-AdAnalysisNumber $_.SidHistoryCount
            $null -ne $count -and $count -gt 0
        }).Count
    if ($usersSidHistoryCount -eq 0) { $usersSidHistoryCount = @($allUsersSidHistory).Count }

    $passwordAgeOver365Count = @($allUsers | Where-Object {
            $age = ConvertTo-AdAnalysisNumber $_.PasswordAgeDays
            $null -ne $age -and $age -gt 365
        }).Count

    $objectsRc4OnlyCount = @((@($allUsers) + @($allComputers)) | Where-Object {
            $risk = [string]$_.EncryptionRisk
            $types = [string]$_.EncryptionTypes
            $risk -match 'RC4|NoAES|High' -and $types -notmatch 'AES'
        }).Count

    $weakPasswordPoliciesCount = @($domainSummaries | Where-Object { $_.Summary.WeakPasswordPoliciesCount -gt 0 }).Count
    $privilegedAccountsCount = @($allPrivilegedAccounts).Count
    $adminSdHolderImpactCount = @($allAdminSdHolder).Count
    $asrepRoastableUsersCount = @($allAsrepRoastableUsers).Count
    $unconstrainedDelegationCount = @($allUnconstrainedDelegation).Count
    $protectedUsersCount = @($allProtectedUsers).Count
    $serviceAccountCandidatesCount = @($allServiceAccountCandidates).Count
    $domainControllerCount = @($allDomainControllers).Count
    $gpoCount = @($allGpos).Count
    $ouCount = @($allOus).Count
    $spnCount = @($allSpns).Count
    $fgppCount = [int](($domainSummaries | ForEach-Object { [int]$_.Summary.FGPPCount } | Measure-Object -Sum).Sum)
    $privilegedPasswordAgeOver180Count = @($allPrivilegedPasswordAge | Where-Object {
            $age = ConvertTo-AdAnalysisNumber $_.PasswordAgeDays
            $null -ne $age -and $age -gt 180
        }).Count

    $usersStalePct = if ($usersTotal -gt 0) { [math]::Round(($usersStaleCount / $usersTotal) * 100, 1) } else { 0 }
    $computersStalePct = if ($computersTotal -gt 0) { [math]::Round(($computersStaleCount / $computersTotal) * 100, 1) } else { 0 }
    $usersSidHistoryPct = if ($usersTotal -gt 0) { [math]::Round(($usersSidHistoryCount / $usersTotal) * 100, 1) } else { 0 }
    $usersNonRoutableUPNPct = if ($usersTotal -gt 0) { [math]::Round(($usersNonRoutableUPNCount / $usersTotal) * 100, 1) } else { 0 }
    $allObjectsCount = $usersTotal + $computersTotal
    $objectsRc4OnlyPct = if ($allObjectsCount -gt 0) { [math]::Round(($objectsRc4OnlyCount / $allObjectsCount) * 100, 1) } else { 0 }

    $summary = [pscustomobject]@{
        RunTimestamp                  = if ($index -and $index.generatedAtUtc) { [string]$index.generatedAtUtc } else { Get-AdTimestamp -Format Iso }
        ForestName                    = if ($forestSummary -and $forestSummary.ForestName) { [string]$forestSummary.ForestName } else { 'Unknown' }
        ForestRootDomain              = if ($forestSummary -and $forestSummary.RootDomain) { [string]$forestSummary.RootDomain } else { 'Unknown' }
        DomainsCount                  = @($domainFolders).Count
        TrustCount                    = @($trusts).Count
        UsersTotal                    = $usersTotal
        GroupsTotal                   = $groupsTotal
        ComputersTotal                = $computersTotal
        WorkstationsTotal             = $workstationsTotal
        ServersTotal                  = $serversTotal
        UsersStaleCount               = $usersStaleCount
        UsersStalePct                 = $usersStalePct
        ComputersStaleCount           = $computersStaleCount
        ComputersStalePct             = $computersStalePct
        UsersSIDHistoryCount          = $usersSidHistoryCount
        UsersSIDHistoryPct            = $usersSidHistoryPct
        UsersNonRoutableUPNCount      = $usersNonRoutableUPNCount
        UsersNonRoutableUPNPct        = $usersNonRoutableUPNPct
        ObjectsRC4OnlyCount           = $objectsRc4OnlyCount
        ObjectsRC4OnlyPct             = $objectsRc4OnlyPct
        PrivilegedAccountsCount       = $privilegedAccountsCount
        EmptyGroupsCount              = 0
        DuplicateSpnsCount            = 0
        WeakPasswordPoliciesCount     = $weakPasswordPoliciesCount
        HighDepthGroupsCount          = 0
        HighDepthOUsCount             = 0
        CrossDomainDependenciesCount  = 0
        DisabledUsersCount            = $disabledUsersCount
        DisabledComputersCount        = $disabledComputersCount
        AdminSdHolderImpactCount      = $adminSdHolderImpactCount
        FsmoUnavailableCount          = 0
        HighCostSiteLinksCount        = 0
        LowTombstoneLifetimeCount     = 0
        TopServiceTypesCount          = 0
        AsrepRoastableUsersCount      = $asrepRoastableUsersCount
        UnconstrainedDelegationCount  = $unconstrainedDelegationCount
        ProtectedUsersCount           = $protectedUsersCount
        ServiceAccountCandidatesCount = $serviceAccountCandidatesCount
        DomainControllerCount         = $domainControllerCount
        GpoCount                      = $gpoCount
        OuCount                       = $ouCount
        SpnCount                      = $spnCount
        FGPPCount                     = $fgppCount
        PrivilegedPasswordAgeOver180Count = $privilegedPasswordAgeOver180Count
        UpnSuffixCount                = @($upnSuffixes).Count
        SiteCount                     = @($sites).Count
        SiteLinkCount                 = @($siteLinks).Count
        AdcsEnterpriseCaCount         = @($adcsEnterpriseCas).Count
    }

    $riskSummary = @(
        New-AdDiscoveryRiskRow -Flag 'StaleLastLogonOver180d' -Severity 'High' -Count $usersStaleCount -Description 'User accounts with stale logon activity.' -Recommendation 'Audit and disable inactive users before migration.'
        New-AdDiscoveryRiskRow -Flag 'ComputerStaleLastLogonOver90d' -Severity 'Medium' -Count $computersStaleCount -Description 'Computer accounts with stale logon activity.' -Recommendation 'Retire or disable orphaned device objects.'
        New-AdDiscoveryRiskRow -Flag 'PasswordAgeOver365d' -Severity 'High' -Count $passwordAgeOver365Count -Description 'Accounts with passwords older than 365 days.' -Recommendation 'Force password resets for aged credentials.'
        New-AdDiscoveryRiskRow -Flag 'PrivilegedPasswordAgeOver180d' -Severity 'High' -Count $privilegedPasswordAgeOver180Count -Description 'Privileged accounts with aged passwords.' -Recommendation 'Rotate privileged credentials before migration cutover.'
        New-AdDiscoveryRiskRow -Flag 'UPN_NonRoutableSuffix' -Severity 'Medium' -Count $usersNonRoutableUPNCount -Description 'Users with non-routable UPN suffixes.' -Recommendation 'Normalize UPN suffixes to routable domains.'
        New-AdDiscoveryRiskRow -Flag 'Kerberos_NoAES' -Severity 'High' -Count $objectsRc4OnlyCount -Description 'Objects that appear to lack AES support.' -Recommendation 'Enable modern Kerberos encryption before migration.'
        New-AdDiscoveryRiskRow -Flag 'WeakPasswordPolicy' -Severity 'High' -Count $weakPasswordPoliciesCount -Description 'Domains with weak default password policies.' -Recommendation 'Strengthen default password policy settings.'
        New-AdDiscoveryRiskRow -Flag 'SIDHistoryPresent' -Severity 'Medium' -Count $usersSidHistoryCount -Description 'Users with SID history present.' -Recommendation 'Review and clean SID history after migration dependencies are closed.'
        New-AdDiscoveryRiskRow -Flag 'AdminSDHolderProtected' -Severity 'High' -Count $adminSdHolderImpactCount -Description 'Objects protected by AdminSDHolder.' -Recommendation 'Validate delegated access and privileged group memberships.'
        New-AdDiscoveryRiskRow -Flag 'UnconstrainedDelegation' -Severity 'High' -Count $unconstrainedDelegationCount -Description 'Accounts or computers trusted for unconstrained delegation.' -Recommendation 'Move to constrained delegation or remove delegation where possible.'
        New-AdDiscoveryRiskRow -Flag 'AsrepRoastableUsers' -Severity 'High' -Count $asrepRoastableUsersCount -Description 'Accounts vulnerable to AS-REP roasting.' -Recommendation 'Enable pre-authentication for affected users.'
    ) | Where-Object { $_ }

    return [pscustomobject]@{
        RunRoot        = $RunRoot
        Environment    = if ($index -and $index.environment) { [string]$index.environment } else { 'Unknown' }
        CustomerName   = if ($index -and $index.customerName) { [string]$index.customerName } else { '' }
        GeneratedAtUtc = if ($index -and $index.generatedAtUtc) { [string]$index.generatedAtUtc } else { $summary.RunTimestamp }
        Summary        = $summary
        DomainSummaries = @($domainSummaries)
        RiskSummary    = @($riskSummary)
        Trusts         = @($trusts)
        UpnSuffixes    = @($upnSuffixes)
        Sites          = @($sites)
        SiteLinks      = @($siteLinks)
        DomainFolders  = @($domainFolders)
    }
}
