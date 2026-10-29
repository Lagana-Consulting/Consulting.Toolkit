function Get-AdAssessmentSummary {
    <#
    .SYNOPSIS
    Generates comprehensive forest-level assessment metrics.

    .DESCRIPTION
    Aggregates and calculates key statistics across all forest objects:
    - User/computer/group totals
    - Stale account percentages
    - SID history usage
    - Privileged account counts
    - Encryption risk indicators
    - Extended assessment metrics (nesting, cross-domain, FSMO, etc.)

    Produces a single summary row suitable for executive reporting.

    .PARAMETER ForestName
    Forest DNS name for the assessment. Required.

    .PARAMETER AllUsers
    Array of all user objects from Get-AdAdUsers. Required.

    .PARAMETER AllComputers
    Array of all computer objects from Get-AdAdComputers. Required.

    .PARAMETER AllGroups
    Array of all group objects from Get-AdAdGroups. Required.

    .PARAMETER PrivilegedAccounts
    Array of privileged account objects from Get-AdPrivilegedAccounts. Required.

    .PARAMETER StaleUserThresholdDays
    Days since last logon to consider user stale. Default is 180.

    .PARAMETER StaleComputerThresholdDays
    Days since last logon to consider computer stale. Default is 90.

    .PARAMETER GroupNestingData
    Optional array from Get-AdGroupNestingDepth for nesting metrics.

    .PARAMETER CrossDomainMembershipData
    Optional array from Get-AdCrossDomainGroupMembership.

    .PARAMETER WeakPasswordPoliciesData
    Optional array from Get-AdWeakPasswordPolicies.

    .PARAMETER EmptyGroupsData
    Optional array from Get-AdEmptyGroups.

    .PARAMETER DuplicateSpnsData
    Optional array from Get-AdDuplicateSpns.

    .PARAMETER DisabledAccountsData
    Optional array from Get-AdDisabledAccounts.

    .PARAMETER AdminSdHolderData
    Optional array from Get-AdAdminSdHolderImpact.

    .PARAMETER FsmoAvailabilityData
    Optional array from Get-AdFsmoRoleAvailability.

    .PARAMETER OuDepthData
    Optional array from Get-AdOuDepthAnalysis.

    .PARAMETER TopSpnsData
    Optional array from Get-AdTopSpnsByType.

    .PARAMETER SiteLinkData
    Optional array from Get-AdSiteLinkCostAnalysis.

    .PARAMETER TombstoneData
    Optional array from Get-AdTombstoneLifetime.

    .EXAMPLE
    $summary = Get-AdAssessmentSummary `
      -ForestName "contoso.com" `
      -AllUsers $users `
      -AllComputers $computers `
      -AllGroups $groups `
      -PrivilegedAccounts $privAccounts

    Generates basic assessment summary.

    .EXAMPLE
    $summary = Get-AdAssessmentSummary `
      -ForestName "contoso.com" `
      -AllUsers $users `
      -AllComputers $computers `
      -AllGroups $groups `
      -PrivilegedAccounts $privAccounts `
      -GroupNestingData $nesting `
      -WeakPasswordPoliciesData $weakPwd `
      -StaleUserThresholdDays 90

    Generates extended assessment with custom stale threshold.

    .OUTPUTS
    PSCustomObject with comprehensive assessment metrics including:
    - ForestName, DomainCount
    - UserTotal, UserStaleCount, UserStalePct
    - ComputerTotal, ComputerStaleCount, ComputerStalePct
    - GroupTotal, PrivilegedAccountCount
    - UserSidHistoryCount, ComputerSidHistoryCount
    - EncryptionHighRisk counts
    - Extended metrics (if optional data provided)

    .NOTES
    Primary input for forest-level assessment reports.
    Optional parameters enhance metrics but are not required.
    All percentage calculations handle zero-division safely.

    .LINK
    Get-AdAdUsers
    Get-AdPrivilegedAccounts
    New-AdComprehensiveAssessmentReport
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ForestName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllUsers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllComputers,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$AllGroups,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$PrivilegedAccounts,

        [ValidateRange(0, [int]::MaxValue)][int]$StaleUserThresholdDays = 180,

        [ValidateRange(0, [int]::MaxValue)][int]$StaleComputerThresholdDays = 90,

        # Extended assessment data
        [array]$GroupNestingData,
        [array]$CrossDomainMembershipData,
        [array]$WeakPasswordPoliciesData,
        [array]$EmptyGroupsData,
        [array]$DuplicateSpnsData,
        [array]$DisabledAccountsData,
        [array]$AdminSdHolderData,
        [array]$FsmoAvailabilityData,
        [array]$OuDepthData,
        [array]$TopSpnsData,
        [array]$SiteLinkData,
        [array]$TombstoneData
    )

    $forest = Get-AdAdForest -ForestName $ForestName
    $domains = @(Get-AdAdDomains -Forest $forest)

    $usersTotal = @($AllUsers).Count
    $groupsTotal = @($AllGroups).Count
    $computersTotal = @($AllComputers).Count

    # Stale users (LastLogonDays > threshold)
    $usersStale = @($AllUsers | Where-Object {
            (ConvertTo-AdAssessmentInteger $_.LastLogonDays -Field 'LastLogonDays') -gt $StaleUserThresholdDays
        })
    $usersStaleCount = $usersStale.Count
    $usersStalePct = if ($usersTotal -gt 0) { [math]::Round(($usersStaleCount / $usersTotal) * 100, 2) } else { 0 }

    # Stale computers
    $computersStale = @($AllComputers | Where-Object {
            (ConvertTo-AdAssessmentInteger $_.LastLogonDays -Field 'LastLogonDays') -gt $StaleComputerThresholdDays
        })
    $computersStaleCount = $computersStale.Count
    $computersStalePct = if ($computersTotal -gt 0) { [math]::Round(($computersStaleCount / $computersTotal) * 100, 2) } else { 0 }

    # SID history
    $usersSidHistory = @($AllUsers | Where-Object {
            (ConvertTo-AdAssessmentInteger $_.SidHistoryCount -Field 'SidHistoryCount') -gt 0
        })
    $usersSidHistoryCount = $usersSidHistory.Count
    $usersSidHistoryPct = if ($usersTotal -gt 0) { [math]::Round(($usersSidHistoryCount / $usersTotal) * 100, 2) } else { 0 }

    # Non-routable UPN
    $usersNonRoutableUpn = @($AllUsers | Where-Object {
            (ConvertTo-AdAssessmentBoolean $_.IsNonRoutableUpnSuffix -Field 'IsNonRoutableUpnSuffix') -eq $true
        })
    $usersNonRoutableUpnCount = $usersNonRoutableUpn.Count
    $usersNonRoutableUpnPct = if ($usersTotal -gt 0) { [math]::Round(($usersNonRoutableUpnCount / $usersTotal) * 100, 2) } else { 0 }

    # Count advertised RC4 support without AES, independently of the risk label.
    $allObjects = @(@($AllUsers) + @($AllComputers))
    $objectsRC4Only = @($allObjects | Where-Object {
            (Get-AdAssessmentEncryptionState $_.EncryptionTypes).Rc4WithoutAes
        })
    $objectsRC4OnlyCount = $objectsRC4Only.Count
    $objectsRC4OnlyPct = if ($allObjects.Count -gt 0) { [math]::Round(($objectsRC4OnlyCount / $allObjects.Count) * 100, 2) } else { 0 }

    # Extended assessment metrics
    $emptyGroupsCount = if ($EmptyGroupsData) { @($EmptyGroupsData).Count } else { 0 }
    $duplicateSpnsCount = if ($DuplicateSpnsData) { @($DuplicateSpnsData).Count } else { 0 }
    $weakPasswordPoliciesCount = if ($WeakPasswordPoliciesData) { @($WeakPasswordPoliciesData | Where-Object { (ConvertTo-AdAssessmentInteger $_.WeaknessCount -Field 'WeaknessCount') -ge 3 }).Count } else { 0 }

    $highDepthGroupsCount = if ($GroupNestingData) { @($GroupNestingData | Where-Object { (ConvertTo-AdAssessmentInteger $_.NestingDepth -Field 'NestingDepth') -ge 5 }).Count } else { 0 }
    $highDepthOUsCount = if ($OuDepthData) { @($OuDepthData | Where-Object { (ConvertTo-AdAssessmentInteger $_.Depth -Field 'Depth') -ge 5 }).Count } else { 0 }

    $crossDomainDependenciesCount = if ($CrossDomainMembershipData) { @($CrossDomainMembershipData).Count } else { 0 }

    $disabledUsersCount = if ($DisabledAccountsData) { @($DisabledAccountsData | Where-Object { $_.ObjectClass -eq 'User' }).Count } else { 0 }
    $disabledComputersCount = if ($DisabledAccountsData) { @($DisabledAccountsData | Where-Object { $_.ObjectClass -eq 'Computer' }).Count } else { 0 }

    $adminSdHolderImpactCount = if ($AdminSdHolderData) { @($AdminSdHolderData).Count } else { 0 }

    $fsmoUnavailableCount = if ($FsmoAvailabilityData) { @($FsmoAvailabilityData | Where-Object { (ConvertTo-AdAssessmentBoolean $_.IsAvailable -Field 'IsAvailable') -eq $false }).Count } else { 0 }

    $highCostSiteLinksCount = if ($SiteLinkData) { @($SiteLinkData | Where-Object {
        # Cost is authoritative; accept historical labels if a legacy row lacks it.
        if ($_.PSObject.Properties['Cost']) {
            (ConvertTo-AdAssessmentInteger $_.Cost -Field 'Cost') -gt 500
        } else { $_.Assessment -in @('High Cost', 'Very High Cost', 'High', 'Very High') }
    }).Count } else { 0 }

    $lowTombstoneLifetimeCount = if ($TombstoneData) { @($TombstoneData | Where-Object { $_.Status -eq 'Low (Risk)' }).Count } else { 0 }

    $topServiceTypesCount = if ($TopSpnsData) { @($TopSpnsData).Count } else { 0 }

    [pscustomobject]@{
        RunTimestamp                 = [datetime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        ForestName                   = [string]$forest.Name
        ForestRootDomain             = [string]$forest.RootDomain
        DomainsCount                 = $domains.Count
        UsersTotal                   = $usersTotal
        GroupsTotal                  = $groupsTotal
        ComputersTotal               = $computersTotal
        UsersStaleCount              = $usersStaleCount
        UsersStalePct                = $usersStalePct
        ComputersStaleCount          = $computersStaleCount
        ComputersStalePct            = $computersStalePct
        UsersSIDHistoryCount         = $usersSidHistoryCount
        UsersSIDHistoryPct           = $usersSidHistoryPct
        UsersNonRoutableUPNCount     = $usersNonRoutableUpnCount
        UsersNonRoutableUPNPct       = $usersNonRoutableUpnPct
        ObjectsRC4OnlyCount          = $objectsRC4OnlyCount
        ObjectsRC4OnlyPct            = $objectsRC4OnlyPct
        PrivilegedAccountsCount      = @($PrivilegedAccounts).Count
        EmptyGroupsCount             = $emptyGroupsCount
        DuplicateSpnsCount           = $duplicateSpnsCount
        WeakPasswordPoliciesCount    = $weakPasswordPoliciesCount
        HighDepthGroupsCount         = $highDepthGroupsCount
        HighDepthOUsCount            = $highDepthOUsCount
        CrossDomainDependenciesCount = $crossDomainDependenciesCount
        DisabledUsersCount           = $disabledUsersCount
        DisabledComputersCount       = $disabledComputersCount
        AdminSdHolderImpactCount     = $adminSdHolderImpactCount
        FsmoUnavailableCount         = $fsmoUnavailableCount
        HighCostSiteLinksCount       = $highCostSiteLinksCount
        LowTombstoneLifetimeCount    = $lowTombstoneLifetimeCount
        TopServiceTypesCount         = $topServiceTypesCount
    }
}
