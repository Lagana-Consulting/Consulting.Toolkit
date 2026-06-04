function New-AdMigrationPlanningPackage {
    <#
    .SYNOPSIS
    Build an internal migration planning package from one or more discovery runs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SourceRunRoot,

        [string]$TargetRunRoot,

        [string]$OutputRoot,

        [string]$CustomerName = 'Organization',

        [string]$PlanningConfigPath,

        [switch]$IncludeNonRoutableUpnUsers,

        [switch]$CreateCustomerPackage,

        [switch]$ZipCustomerPackage
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function ConvertTo-HtmlText {
        param([AllowNull()][object]$Value)

        if ($null -eq $Value) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }

    function Get-RelativePath {
        param(
            [Parameter(Mandatory)][string]$BasePath,
            [Parameter(Mandatory)][string]$ChildPath
        )

        $baseUri = [System.Uri]((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\')
        $childUri = [System.Uri](Resolve-Path -LiteralPath $ChildPath).Path
        return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
    }

    function ConvertTo-SafeFileName {
        param(
            [AllowNull()][string]$Value,
            [string]$Fallback = 'Organization'
        )

        $name = if ([string]::IsNullOrWhiteSpace($Value)) { $Fallback } else { $Value.Trim() }
        $invalidPattern = ('[{0}]' -f [regex]::Escape(([System.IO.Path]::GetInvalidFileNameChars() -join '')))
        $safeName = ($name -replace $invalidPattern, '_').Trim()
        $safeName = ($safeName -replace '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($safeName)) {
            return $Fallback
        }

        return $safeName
    }

    function Export-CustomerEditableCsv {
        param(
            [Parameter(Mandatory)][string]$SourcePath,
            [Parameter(Mandatory)][string]$DestinationPath
        )

        $editableColumns = @(
            'CustomerDecision',
            'Owner',
            'Comment',
            'RequiredAction'
        )

        $rawLines = @(Get-Content -LiteralPath $SourcePath -Encoding UTF8)
        if ($rawLines.Count -eq 0) {
            $editableColumns -join ',' | Set-Content -LiteralPath $DestinationPath -Encoding UTF8
            return
        }

        $rows = @(Import-Csv -LiteralPath $SourcePath)
        $headers = if ($rows.Count -gt 0) {
            @($rows[0].PSObject.Properties.Name)
        }
        else {
            @(
                ($rawLines[0] -split ',') |
                    ForEach-Object { $_.Trim().Trim('"') } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }
        $allHeaders = @($headers + ($editableColumns | Where-Object { $_ -notin $headers }))

        if ($rows.Count -eq 0) {
            $allHeaders -join ',' | Set-Content -LiteralPath $DestinationPath -Encoding UTF8
            return
        }

        $exportRows = @(
            foreach ($row in $rows) {
                $orderedRow = [ordered]@{}
                foreach ($header in $allHeaders) {
                    $property = $row.PSObject.Properties[$header]
                    $orderedRow[$header] = if ($property) { $property.Value } else { '' }
                }
                [pscustomobject]$orderedRow
            }
        )

        @($exportRows) | Export-Csv -LiteralPath $DestinationPath -NoTypeInformation -Encoding UTF8 -Force
    }

    function Export-DiscoveryCsvRollup {
        param(
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][string]$Filter,
            [Parameter(Mandatory)][string]$DestinationPath,
            [Parameter(Mandatory)][string[]]$DefaultHeaders
        )

        $domainRoot = Join-Path $RunRoot '20_domains'
        $files = @()
        if (Test-Path -LiteralPath $domainRoot -PathType Container) {
            $files = @(
                Get-ChildItem -LiteralPath $domainRoot -Recurse -Filter $Filter -File -ErrorAction SilentlyContinue |
                    Sort-Object FullName
            )
        }

        $rows = New-Object System.Collections.Generic.List[object]
        $headers = New-Object System.Collections.Generic.List[string]

        foreach ($file in $files) {
            $rawLines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -TotalCount 1)
            if ($rawLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($rawLines[0])) {
                foreach ($header in @($rawLines[0] -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })) {
                    if (-not $headers.Contains($header)) { [void]$headers.Add($header) }
                }
            }

            foreach ($row in @(Import-Csv -LiteralPath $file.FullName)) {
                [void]$rows.Add($row)
            }
        }

        if ($headers.Count -eq 0) {
            foreach ($header in $DefaultHeaders) { [void]$headers.Add($header) }
        }

        if ($rows.Count -eq 0) {
            ($headers.ToArray() -join ',') | Set-Content -LiteralPath $DestinationPath -Encoding UTF8
            return 0
        }

        @($rows.ToArray()) | Export-Csv -LiteralPath $DestinationPath -NoTypeInformation -Encoding UTF8 -Force
        return $rows.Count
    }

    $timestamp = Get-AdPlanningTimestamp

    if (-not $OutputRoot) {
        if ($SourceRunRoot.Count -eq 1) {
            $OutputRoot = Join-Path $SourceRunRoot[0] '60_migration_planning'
        }
        else {
            $OutputRoot = Join-Path (Get-Location).Path "MigrationPlanning_$timestamp"
        }
    }

    foreach ($dir in @($OutputRoot, (Join-Path $OutputRoot 'prerequisites'), (Join-Path $OutputRoot 'sources'))) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    Write-Host "Building migration planning package..." -ForegroundColor Cyan
    Write-Host "  Output: $OutputRoot" -ForegroundColor Gray
    foreach ($sourcePath in @($SourceRunRoot)) {
        Write-Host "  Source: $sourcePath" -ForegroundColor Gray
    }
    if ($TargetRunRoot) {
        Write-Host "  Target: $TargetRunRoot" -ForegroundColor Gray
    }

    $prereqRoot = Join-Path $OutputRoot 'prerequisites'
    $prereqs = Test-AdMigrationPrerequisites -SourceRunRoot $SourceRunRoot -TargetRunRoot $TargetRunRoot -OutputRoot $prereqRoot -PlanningConfigPath $PlanningConfigPath

    $sourcePackages = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $SourceRunRoot.Count; $i++) {
        $sourcePath = $SourceRunRoot[$i]
        $label = Get-AdPlanningPackageLabel -RunRoot $sourcePath -Index ($i + 1)
        $sourceRoot = Join-Path (Join-Path $OutputRoot 'sources') $label
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
        }

        $runData = Get-AdPlanningRunData -RunRoot $sourcePath
        $includeUsersPath = Join-Path $sourceRoot 'AD__Migration__Include__Users.csv'
        $includeGroupsPath = Join-Path $sourceRoot 'AD__Migration__Include__Groups.csv'
        $includeComputersPath = Join-Path $sourceRoot 'AD__Migration__Include__Computers.csv'
        $excludePath = Join-Path $sourceRoot 'AD__Migration__Exclude__Candidates.csv'
        $userReviewPath = Join-Path $sourceRoot 'AD__Migration__Review__UserAccounts.csv'
        $duplicatePath = Join-Path $sourceRoot 'AD__Migration__Review__DuplicateConflicts.csv'
        $emptyGroupsPath = Join-Path $sourceRoot 'AD__Migration__Review__EmptyGroups.csv'
        $singleMemberGroupsPath = Join-Path $sourceRoot 'AD__Migration__Review__SingleMemberGroups.csv'
        $disabledInactiveGroupsPath = Join-Path $sourceRoot 'AD__Migration__Review__GroupsWithDisabledOrInactiveMembers.csv'

        $usersInclude = New-AdMigrationIncludeFile -RunRoot $sourcePath -ObjectType Users -OutputPath $includeUsersPath -PlanningConfigPath $PlanningConfigPath -IncludeNonRoutableUpnUsers:$IncludeNonRoutableUpnUsers
        $groupsInclude = New-AdMigrationIncludeFile -RunRoot $sourcePath -ObjectType Groups -OutputPath $includeGroupsPath -PlanningConfigPath $PlanningConfigPath
        $computersInclude = New-AdMigrationIncludeFile -RunRoot $sourcePath -ObjectType Computers -OutputPath $includeComputersPath -PlanningConfigPath $PlanningConfigPath
        $exclude = New-AdMigrationExcludeFile -RunRoot $sourcePath -OutputPath $excludePath -PlanningConfigPath $PlanningConfigPath
        $emptyGroupsCount = Export-DiscoveryCsvRollup -RunRoot $sourcePath -Filter 'AD__Domain__Identity__GroupsEmpty__*.csv' -DestinationPath $emptyGroupsPath -DefaultHeaders @('DomainFqdn', 'GroupName', 'GroupSamAccountName', 'GroupDistinguishedName', 'GroupCategory', 'GroupScope', 'MemberCount', 'WhenCreated', 'WhenChanged', 'Description')
        $singleMemberGroupsCount = Export-DiscoveryCsvRollup -RunRoot $sourcePath -Filter 'AD__Domain__Identity__GroupsSingleMember__*.csv' -DestinationPath $singleMemberGroupsPath -DefaultHeaders @('DomainFqdn', 'GroupName', 'GroupSamAccountName', 'GroupDistinguishedName', 'GroupCategory', 'GroupScope', 'MemberCount', 'MemberName', 'MemberSamAccountName', 'MemberObjectClass', 'MemberDistinguishedName', 'MemberEnabled', 'LastLogonTimestampUtc', 'LastLogonDays', 'WhenCreated', 'WhenChanged', 'Description')
        $disabledInactiveGroupsCount = Export-DiscoveryCsvRollup -RunRoot $sourcePath -Filter 'AD__Domain__Identity__GroupsWithDisabledOrInactiveMembers__*.csv' -DestinationPath $disabledInactiveGroupsPath -DefaultHeaders @('DomainFqdn', 'GroupName', 'GroupSamAccountName', 'GroupDistinguishedName', 'GroupCategory', 'GroupScope', 'GroupMemberCount', 'MemberName', 'MemberSamAccountName', 'MemberObjectClass', 'MemberDistinguishedName', 'MemberEnabled', 'LastLogonTimestampUtc', 'LastLogonDays', 'InactiveThresholdDays', 'IsDisabled', 'IsInactive', 'FindingReason', 'LookupError')

        $includedUserSamAccountNames = @(
            @($usersInclude.Rows) |
                Where-Object { [string]$_.ObjectClass -eq 'User' } |
                ForEach-Object { ([string]$_.SamAccountName).Trim().ToLowerInvariant() } |
                Sort-Object -Unique
        )
        $userByKey = @{}
        foreach ($user in @($runData.Users)) {
            $key = ("{0}|{1}" -f ([string]$user.DomainFqdn).Trim().ToLowerInvariant(), ([string]$user.SamAccountName).Trim().ToLowerInvariant())
            $userByKey[$key] = $user
        }

        $serviceByKey = @{}
        foreach ($service in @($runData.ServiceAccounts)) {
            $key = ("{0}|{1}" -f ([string]$service.DomainFqdn).Trim().ToLowerInvariant(), ([string]$service.SamAccountName).Trim().ToLowerInvariant())
            $serviceByKey[$key] = $service
        }

        $privilegedByKey = @{}
        foreach ($privileged in @($runData.PrivilegedAccounts)) {
            $key = ("{0}|{1}" -f ([string]$privileged.DomainFqdn).Trim().ToLowerInvariant(), ([string]$privileged.SamAccountName).Trim().ToLowerInvariant())
            $privilegedByKey[$key] = $privileged
        }

        $reviewByKey = @{}

        foreach ($service in @($runData.ServiceAccounts)) {
            $key = ("{0}|{1}" -f ([string]$service.DomainFqdn).Trim().ToLowerInvariant(), ([string]$service.SamAccountName).Trim().ToLowerInvariant())
            $reviewByKey[$key] = $true
        }
        foreach ($privileged in @($runData.PrivilegedAccounts)) {
            $key = ("{0}|{1}" -f ([string]$privileged.DomainFqdn).Trim().ToLowerInvariant(), ([string]$privileged.SamAccountName).Trim().ToLowerInvariant())
            $reviewByKey[$key] = $true
        }
        foreach ($user in @($runData.Users)) {
            $sam = ([string]$user.SamAccountName).Trim().ToLowerInvariant()
            if ((Test-AdPlanningBoolean $user.IsNonRoutableUpnSuffix) -and ($sam -notin $includedUserSamAccountNames)) {
                $key = ("{0}|{1}" -f ([string]$user.DomainFqdn).Trim().ToLowerInvariant(), $sam)
                $reviewByKey[$key] = $true
            }
        }

        $userReviewRows = @(
            foreach ($key in @($reviewByKey.Keys | Sort-Object)) {
                $user = if ($userByKey.ContainsKey($key)) { $userByKey[$key] } else { $null }
                $service = if ($serviceByKey.ContainsKey($key)) { $serviceByKey[$key] } else { $null }
                $privileged = if ($privilegedByKey.ContainsKey($key)) { $privilegedByKey[$key] } else { $null }

                $domainFqdn = if ($user) { [string]$user.DomainFqdn } elseif ($service) { [string]$service.DomainFqdn } else { [string]$privileged.DomainFqdn }
                $samAccountName = if ($user) { [string]$user.SamAccountName } elseif ($service) { [string]$service.SamAccountName } else { [string]$privileged.SamAccountName }
                $name = if ($user) { [string]$user.Name } else { '' }
                $distinguishedName = if ($user) { [string]$user.DistinguishedName } elseif ($privileged) { [string]$privileged.DistinguishedName } else { '' }
                $userPrincipalName = if ($user) { [string]$user.UserPrincipalName } elseif ($service) { [string]$service.UserPrincipalName } else { '' }
                $enabled = if ($user) { [string]$user.Enabled } elseif ($service) { [string]$service.Enabled } else { '' }
                $lastLogonDays = if ($user) { [string]$user.LastLogonDays } elseif ($service) { [string]$service.LastLogonDays } else { '' }
                $passwordAgeDays = if ($user) { [string]$user.PasswordAgeDays } elseif ($service) { [string]$service.PasswordAgeDays } else { '' }
                $upnSuffix = if ($user) { [string]$user.UPNSuffix } else { '' }
                $isNonRoutableUpn = if ($user) { Test-AdPlanningBoolean $user.IsNonRoutableUpnSuffix } else { $false }
                $isServiceAccountCandidate = $null -ne $service
                $serviceHeuristics = if ($service) { [string]$service.HeuristicFlags } else { '' }
                $passwordNeverExpires = if ($service) { [string]$service.PasswordNeverExpires } else { '' }
                $spnCount = if ($service) { [string]$service.SPNCount } else { if ($user) { [string]$user.SPNCount } else { '' } }
                $isPrivilegedAccount = $null -ne $privileged
                $inPrivGroups = if ($privileged) { [string]$privileged.InPrivGroups } else { 'False' }
                $privGroups = if ($privileged) { [string]$privileged.PrivGroups } else { '' }
                $adminCount = if ($privileged) { [string]$privileged.AdminCount } else { if ($user) { [string]$user.AdminCount } else { '' } }

                $reviewReasons = New-Object System.Collections.Generic.List[string]
                if ($isServiceAccountCandidate) { $reviewReasons.Add('ServiceAccountCandidate') }
                if ($isPrivilegedAccount) { $reviewReasons.Add('PrivilegedAccount') }
                if ($isNonRoutableUpn) { $reviewReasons.Add('NonRoutableUpn') }

                $recommendedHandling = if ($isServiceAccountCandidate -and $isPrivilegedAccount) {
                    'Privileged service account: validate ownership, application dependency, and administrative access before migration.'
                }
                elseif ($isServiceAccountCandidate) {
                    'Service account candidate: validate ownership, authentication method, and application dependency before migration.'
                }
                elseif ($isPrivilegedAccount) {
                    'Privileged account: move into a dedicated privileged migration wave and verify access expectations.'
                }
                else {
                    'Normalize UPN suffix before or during migration planning.'
                }

                [pscustomobject]@{
                    DomainFqdn                 = $domainFqdn
                    SamAccountName             = $samAccountName
                    Name                       = $name
                    DistinguishedName          = $distinguishedName
                    UserPrincipalName          = $userPrincipalName
                    Enabled                    = $enabled
                    LastLogonDays              = $lastLogonDays
                    PasswordAgeDays            = $passwordAgeDays
                    UPNSuffix                  = $upnSuffix
                    IsNonRoutableUpnSuffix     = $isNonRoutableUpn
                    IsServiceAccountCandidate  = $isServiceAccountCandidate
                    ServiceAccountHeuristicFlags = $serviceHeuristics
                    PasswordNeverExpires       = $passwordNeverExpires
                    SPNCount                   = $spnCount
                    IsPrivilegedAccount        = $isPrivilegedAccount
                    InPrivGroups               = $inPrivGroups
                    PrivGroups                 = $privGroups
                    AdminCount                 = $adminCount
                    ReviewReasons              = ($reviewReasons -join ';')
                    RecommendedHandling        = $recommendedHandling
                }
            }
        )
        @($userReviewRows) | Export-Csv -LiteralPath $userReviewPath -NoTypeInformation -Encoding UTF8 -Force

        $duplicateCount = 0
        if ($TargetRunRoot) {
            $dupes = @(Invoke-AdPlanningDuplicateCheck -SourceRunRoot $sourcePath -TargetRunRoot $TargetRunRoot -OutputRoot $sourceRoot)
            $duplicateCount = $dupes.Count
            if ($dupes.Count -gt 0) {
                @($dupes) | Select-Object ConflictType, ConflictValue, ObjectClasses, ConflictCount, ConflictingDomains, Severity, Recommendation |
                    Export-Csv -LiteralPath $duplicatePath -NoTypeInformation -Encoding UTF8 -Force
            }
        }

        $sourceReadmePath = Join-Path $sourceRoot 'README.md'
        @(
            "# Migration Planning Files - $($runData.Summary.ForestName)",
            "",
            "- `AD__Migration__Include__Users.csv`: default user candidates for standard migration waves$(if ($IncludeNonRoutableUpnUsers) { ', including users with non-routable UPN suffixes.' } else { '.' })",
            "- `AD__Migration__Include__Groups.csv`: non-built-in group candidates.",
            "- `AD__Migration__Include__Computers.csv`: active workstation and server candidates.",
            "- `AD__Migration__Exclude__Candidates.csv`: objects that should be excluded from default waves or reviewed separately.",
            "- `AD__Migration__Review__UserAccounts.csv`: one row per reviewed user account with flags for service-account, privileged, and non-routable UPN handling.",
            "- `AD__Migration__Review__EmptyGroups.csv`: empty groups from discovery for cleanup and scope review.",
            "- `AD__Migration__Review__SingleMemberGroups.csv`: groups with exactly one direct member from discovery.",
            "- `AD__Migration__Review__GroupsWithDisabledOrInactiveMembers.csv`: groups with disabled or inactive direct members from discovery.",
            $(if ($TargetRunRoot) { "- `AD__Migration__Review__DuplicateConflicts.csv`: source-to-target identity conflicts detected from current discovery data." } else { '' })
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Set-Content -LiteralPath $sourceReadmePath -Encoding UTF8

        [void]$sourcePackages.Add([pscustomobject]@{
            Label                 = $label
            SourceRunRoot         = $sourcePath
            ForestName            = $runData.Summary.ForestName
            IncludeUsersPath      = $includeUsersPath
            IncludeUsersCount     = $usersInclude.Count
            IncludeNonRoutableUpnUsers = [bool]$IncludeNonRoutableUpnUsers
            IncludeGroupsPath     = $includeGroupsPath
            IncludeGroupsCount    = $groupsInclude.Count
            IncludeComputersPath  = $includeComputersPath
            IncludeComputersCount = $computersInclude.Count
            ExcludePath           = $excludePath
            ExcludeCount          = $exclude.Count
            UserReviewPath        = $userReviewPath
            UserReviewCount       = @($userReviewRows).Count
            EmptyGroupsPath       = $emptyGroupsPath
            EmptyGroupsCount      = $emptyGroupsCount
            SingleMemberGroupsPath = $singleMemberGroupsPath
            SingleMemberGroupsCount = $singleMemberGroupsCount
            DisabledInactiveGroupsPath = $disabledInactiveGroupsPath
            DisabledInactiveGroupsCount = $disabledInactiveGroupsCount
            ServiceReviewCount    = @($runData.ServiceAccounts).Count
            PrivilegedReviewCount = @($runData.PrivilegedAccounts).Count
            NonRoutableUpnCount   = @($userReviewRows | Where-Object { $_.IsNonRoutableUpnSuffix }).Count
            DuplicatePath         = if ($duplicateCount -gt 0) { $duplicatePath } else { $null }
            DuplicateCount        = $duplicateCount
            ReadmePath            = $sourceReadmePath
        })
    }

    $manifestPath = Join-Path $OutputRoot 'MigrationPlanningPackage.json'
    $readmePath = Join-Path $OutputRoot 'README.md'

    $manifest = [pscustomobject]@{
        GeneratedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
        CustomerName      = $CustomerName
        SourceRunRoot     = @($SourceRunRoot)
        TargetRunRoot     = $TargetRunRoot
        OutputRoot        = $OutputRoot
        IncludeNonRoutableUpnUsers = [bool]$IncludeNonRoutableUpnUsers
        CreateCustomerPackage = [bool]$CreateCustomerPackage
        ZipCustomerPackage = [bool]$ZipCustomerPackage
        Prerequisites     = [pscustomobject]@{
            CsvPath      = $prereqs.CsvPath
            JsonPath     = $prereqs.JsonPath
            WarningCount = $prereqs.WarningCount
            FailureCount = $prereqs.FailureCount
        }
        SourcePackages    = $sourcePackages.ToArray()
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    @(
        "# Migration Planning Package",
        "",
        "Customer: $CustomerName",
        "Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
        "",
        "## What is in this package",
        "",
        "- `prerequisites`: checklist-style validation output for migration preparation.",
        "- `sources`: one folder per source environment with include, exclude, and review files.",
        "- `MigrationPlanningPackage.json`: manifest for automation and repeatable internal use.",
        "",
        "## Recommended workflow",
        "",
        "1. Review the prerequisites summary first.",
        "2. Validate default include files with project stakeholders.",
        "3. Work through exclude and review files before building migration waves.",
        $(if ($TargetRunRoot) { "4. Resolve duplicate conflicts before finalizing include scope." } else { "4. Add a target run later to generate duplicate conflict review files." })
    ) | Set-Content -LiteralPath $readmePath -Encoding UTF8

    $customerPackageRoot = $null
    $customerZipPath = $null
    $customerIndexPath = $null
    $customerReadmePath = $null
    $customerChecklistPath = $null
    if ($CreateCustomerPackage) {
        Write-Host "Creating customer planning package..." -ForegroundColor Cyan
        $safeCustomerName = ConvertTo-SafeFileName -Value $CustomerName
        $customerPackageRoot = Join-Path $OutputRoot $safeCustomerName
        $customerReportsRoot = Join-Path $customerPackageRoot 'Reports'
        foreach ($dir in @($customerPackageRoot, $customerReportsRoot)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        $prereqCustomerPath = Join-Path $customerPackageRoot '01-Prerequisites-Summary.csv'
        if ($prereqs.CsvPath -and (Test-Path -LiteralPath $prereqs.CsvPath -PathType Leaf)) {
            Copy-Item -LiteralPath $prereqs.CsvPath -Destination $prereqCustomerPath -Force
        }

        $actionChecklistRows = New-Object System.Collections.Generic.List[object]

        foreach ($sourcePackage in @($sourcePackages.ToArray())) {
            $customerSourceRoot = Join-Path $customerReportsRoot $sourcePackage.Label
            if (-not (Test-Path -LiteralPath $customerSourceRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $customerSourceRoot -Force | Out-Null
            }

            $friendlyMap = @(
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.IncludeUsersPath
                    FriendlyName    = '01-Include-Users.csv'
                    Purpose         = 'Users currently proposed for migration.'
                    CustomerAction  = 'Review each listed user and confirm whether the account should migrate, be deferred, or be removed from scope.'
                    WhatWeNeed      = 'Mark any users that should not migrate and note any users missing from this list that must be added.'
                    AddEditableColumns = $true
                }
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.IncludeGroupsPath
                    FriendlyName    = '02-Include-Groups.csv'
                    Purpose         = 'Groups currently proposed for migration.'
                    CustomerAction  = 'Review whether the listed groups are still needed and should remain in migration scope.'
                    WhatWeNeed      = 'Flag obsolete groups and identify any important groups that are missing.'
                    AddEditableColumns = $true
                }
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.IncludeComputersPath
                    FriendlyName    = '03-Include-Computers.csv'
                    Purpose         = 'Computer accounts currently proposed for migration.'
                    CustomerAction  = 'Confirm which devices are active and should be included in migration planning.'
                    WhatWeNeed      = 'Mark retired, replaced, or out-of-scope devices so they can be removed from migration waves.'
                    AddEditableColumns = $true
                }
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.ExcludePath
                    FriendlyName    = '04-Excluded-Or-Needs-Review.csv'
                    Purpose         = 'Accounts and devices that were excluded from the default migration scope.'
                    CustomerAction  = 'Review whether any excluded objects still need to migrate.'
                    WhatWeNeed      = 'Tell us which excluded rows should be brought back into scope and why.'
                    AddEditableColumns = $true
                }
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.UserReviewPath
                    FriendlyName    = '05-User-Review.csv'
                    Purpose         = 'User accounts needing special handling, including service accounts, privileged accounts, and UPN normalization.'
                    CustomerAction  = 'Review each flagged account and confirm owner, business purpose, migration timing, and any special requirements.'
                    WhatWeNeed      = 'For each flagged account, provide owner, application dependency, whether it must migrate, and whether the current UPN is expected to change.'
                    AddEditableColumns = $true
                }
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.EmptyGroupsPath
                    FriendlyName    = '06-Empty-Groups.csv'
                    Purpose         = 'Groups with no direct members, sourced from the discovery empty-groups dataset.'
                    CustomerAction  = 'Review whether each empty group is still required or can be retired before migration.'
                    WhatWeNeed      = 'Tell us which groups should migrate, be deleted, be archived, or be reviewed with an application or business owner.'
                    AddEditableColumns = $true
                }
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.SingleMemberGroupsPath
                    FriendlyName    = '07-Single-Member-Groups.csv'
                    Purpose         = 'Groups with exactly one direct member, sourced from the discovery single-member-groups dataset.'
                    CustomerAction  = 'Review whether each one-member group still has a valid business or application purpose.'
                    WhatWeNeed      = 'Tell us whether the group should migrate, be consolidated, have membership corrected, or be removed from scope.'
                    AddEditableColumns = $true
                }
                [pscustomobject]@{
                    SourcePath      = $sourcePackage.DisabledInactiveGroupsPath
                    FriendlyName    = '08-Groups-With-Disabled-Or-Inactive-Members.csv'
                    Purpose         = 'Groups that contain disabled or inactive direct members, sourced from the discovery group-membership dataset.'
                    CustomerAction  = 'Review stale or disabled group members and confirm whether membership should be cleaned up before migration.'
                    WhatWeNeed      = 'Tell us which members should remain, be removed, or require owner validation before the group migrates.'
                    AddEditableColumns = $true
                }
            )

            if ($sourcePackage.DuplicatePath) {
                $friendlyMap += [pscustomobject]@{
                    SourcePath      = $sourcePackage.DuplicatePath
                    FriendlyName    = '09-Duplicate-Conflicts.csv'
                    Purpose         = 'Source-to-target naming and identity conflicts detected automatically.'
                    CustomerAction  = 'Review each conflict and decide whether the source object should be renamed, merged, deferred, or treated as a separate identity.'
                    WhatWeNeed      = 'For each conflict, tell us which object should remain authoritative and whether any rename or consolidation is required before migration.'
                    AddEditableColumns = $true
                }
            }

            foreach ($entry in $friendlyMap) {
                if (-not $entry.SourcePath -or -not (Test-Path -LiteralPath $entry.SourcePath -PathType Leaf)) { continue }
                $destinationPath = Join-Path $customerSourceRoot $entry.FriendlyName
                if ($entry.AddEditableColumns) {
                    Export-CustomerEditableCsv -SourcePath $entry.SourcePath -DestinationPath $destinationPath
                }
                else {
                    Copy-Item -LiteralPath $entry.SourcePath -Destination $destinationPath -Force
                }

                [void]$actionChecklistRows.Add([pscustomobject]@{
                    Environment    = $sourcePackage.ForestName
                    FileName       = $entry.FriendlyName
                    Purpose        = $entry.Purpose
                    CustomerAction = $entry.CustomerAction
                    WhatWeNeedBack = $entry.WhatWeNeed
                })
            }

            $sourceGuidePath = Join-Path $customerSourceRoot '00-How-To-Review.txt'
            @(
                "How To Review Files For $($sourcePackage.ForestName)",
                '',
                '1. Start with 01-Include-Users.csv, 02-Include-Groups.csv, and 03-Include-Computers.csv.',
                '2. Remove anything that should not be migrated and note anything missing that must be added.',
                '3. Review 04-Excluded-Or-Needs-Review.csv for objects that may need to be brought back into scope.',
                '4. Review 05-User-Review.csv carefully for service accounts, privileged accounts, and UPN changes.',
                '5. Review 06-Empty-Groups.csv, 07-Single-Member-Groups.csv, and 08-Groups-With-Disabled-Or-Inactive-Members.csv for group cleanup decisions.',
                $(if ($sourcePackage.DuplicatePath) { '6. Review 09-Duplicate-Conflicts.csv and tell us how each conflict should be resolved.' } else { '' }),
                '',
                'Please fill in the CustomerDecision, Owner, Comment, and RequiredAction columns directly in the CSV files and return them to us.'
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Set-Content -LiteralPath $sourceGuidePath -Encoding UTF8
        }

        $customerChecklistPath = Join-Path $customerPackageRoot 'Customer-Action-Checklist.csv'
        @($actionChecklistRows.ToArray()) | Export-Csv -LiteralPath $customerChecklistPath -NoTypeInformation -Encoding UTF8 -Force

        $customerIndexPath = Join-Path $customerPackageRoot 'index.html'
        $customerReadmePath = Join-Path $customerPackageRoot 'README.txt'

        $customerHtml = New-Object System.Text.StringBuilder
        [void]$customerHtml.AppendLine('<!DOCTYPE html>')
        [void]$customerHtml.AppendLine('<html lang="en">')
        [void]$customerHtml.AppendLine('<head>')
        [void]$customerHtml.AppendLine('  <meta charset="UTF-8">')
        [void]$customerHtml.AppendLine('  <meta name="viewport" content="width=device-width, initial-scale=1.0">')
        [void]$customerHtml.AppendLine("  <title>Migration Planning Review - $(ConvertTo-HtmlText $CustomerName)</title>")
        [void]$customerHtml.AppendLine('  <style>')
        [void]$customerHtml.AppendLine("    body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; background: #f5f7fb; color: #22303c; margin: 0; }")
        [void]$customerHtml.AppendLine('    .container { max-width: 1180px; margin: 0 auto; padding: 28px; }')
        [void]$customerHtml.AppendLine('    .hero { background: linear-gradient(135deg, #0b4f6c, #145a7a); color: white; padding: 34px; border-radius: 14px; box-shadow: 0 14px 34px rgba(11,79,108,0.18); }')
        [void]$customerHtml.AppendLine('    .hero h1 { margin: 0 0 10px 0; font-size: 32px; }')
        [void]$customerHtml.AppendLine('    .hero p { margin: 8px 0; opacity: 0.95; }')
        [void]$customerHtml.AppendLine('    .card { background: white; border-radius: 14px; padding: 22px; box-shadow: 0 4px 18px rgba(0,0,0,0.08); margin-top: 20px; }')
        [void]$customerHtml.AppendLine('    h2, h3 { color: #0b4f6c; }')
        [void]$customerHtml.AppendLine('    ul, ol { margin-left: 20px; }')
        [void]$customerHtml.AppendLine('    li { margin: 8px 0; }')
        [void]$customerHtml.AppendLine('    table { width: 100%; border-collapse: collapse; margin-top: 12px; }')
        [void]$customerHtml.AppendLine('    th, td { padding: 10px 8px; border-bottom: 1px solid #dfe6ec; text-align: left; vertical-align: top; }')
        [void]$customerHtml.AppendLine('    th { font-size: 12px; text-transform: uppercase; color: #5c6b77; letter-spacing: 0.04em; }')
        [void]$customerHtml.AppendLine('    a { color: #155d8b; text-decoration: none; font-weight: 600; }')
        [void]$customerHtml.AppendLine('    a:hover { text-decoration: underline; }')
        [void]$customerHtml.AppendLine('    .pill { display: inline-block; background: #e8f4fa; color: #0b4f6c; padding: 5px 10px; border-radius: 999px; font-size: 12px; margin-right: 8px; margin-top: 8px; }')
        [void]$customerHtml.AppendLine('  </style>')
        [void]$customerHtml.AppendLine('</head>')
        [void]$customerHtml.AppendLine('<body>')
        [void]$customerHtml.AppendLine('  <div class="container">')
        [void]$customerHtml.AppendLine('    <div class="hero">')
        [void]$customerHtml.AppendLine('      <h1>Migration Planning Review Package</h1>')
        [void]$customerHtml.AppendLine("      <p>Customer: $(ConvertTo-HtmlText $CustomerName)</p>")
        [void]$customerHtml.AppendLine('      <p>This package is for business and technical review of the proposed migration scope and any accounts or devices that require special handling.</p>')
        [void]$customerHtml.AppendLine('      <p>Please extract the full zip, open this page, and work through the review items in order.</p>')
        [void]$customerHtml.AppendLine('    </div>')
        [void]$customerHtml.AppendLine('    <div class="card">')
        [void]$customerHtml.AppendLine('      <h2>What We Need From You</h2>')
        [void]$customerHtml.AppendLine('      <ol>')
        [void]$customerHtml.AppendLine('        <li>Confirm which users, groups, and computers should migrate.</li>')
        [void]$customerHtml.AppendLine('        <li>Tell us which excluded objects should be brought back into scope.</li>')
        [void]$customerHtml.AppendLine('        <li>Review flagged user accounts and confirm owner, purpose, and any special handling needs.</li>')
        [void]$customerHtml.AppendLine('        <li>Review empty, single-member, and stale-member groups for cleanup or migration decisions.</li>')
        [void]$customerHtml.AppendLine('        <li>If duplicate conflicts are included, tell us which source or target object should remain authoritative.</li>')
        [void]$customerHtml.AppendLine('      </ol>')
        [void]$customerHtml.AppendLine('      <p><strong>Best way to respond:</strong> open the CSV files in Excel and fill in the <code>CustomerDecision</code>, <code>Owner</code>, <code>Comment</code>, and <code>RequiredAction</code> columns directly in each file.</p>')
        [void]$customerHtml.AppendLine('    </div>')
        [void]$customerHtml.AppendLine('    <div class="card">')
        [void]$customerHtml.AppendLine('      <h2>File Guide</h2>')
        [void]$customerHtml.AppendLine('      <table>')
        [void]$customerHtml.AppendLine('        <tr><th>File</th><th>What It Means</th><th>What To Review</th><th>What We Need Back</th></tr>')
        $fileGuideRows = @(
            $actionChecklistRows.ToArray() |
                Sort-Object FileName, Purpose, CustomerAction, WhatWeNeedBack -Unique
        )
        foreach ($row in $fileGuideRows) {
            [void]$customerHtml.AppendLine("        <tr><td>$(ConvertTo-HtmlText $row.FileName)</td><td>$(ConvertTo-HtmlText $row.Purpose)</td><td>$(ConvertTo-HtmlText $row.CustomerAction)</td><td>$(ConvertTo-HtmlText $row.WhatWeNeedBack)</td></tr>")
        }
        [void]$customerHtml.AppendLine('      </table>')
        [void]$customerHtml.AppendLine("      <p style=""margin-top:12px;""><a href=""Customer-Action-Checklist.csv"">Download the action checklist as CSV</a></p>")
        [void]$customerHtml.AppendLine('    </div>')
        [void]$customerHtml.AppendLine('    <div class="card">')
        [void]$customerHtml.AppendLine('      <h2>Packages By Environment</h2>')
        foreach ($sourcePackage in @($sourcePackages.ToArray())) {
            [void]$customerHtml.AppendLine("      <h3>$(ConvertTo-HtmlText $sourcePackage.ForestName)</h3>")
            [void]$customerHtml.AppendLine("      <span class=""pill"">Include Users: $(ConvertTo-HtmlText $sourcePackage.IncludeUsersCount)</span>")
            [void]$customerHtml.AppendLine("      <span class=""pill"">Include Groups: $(ConvertTo-HtmlText $sourcePackage.IncludeGroupsCount)</span>")
            [void]$customerHtml.AppendLine("      <span class=""pill"">Include Computers: $(ConvertTo-HtmlText $sourcePackage.IncludeComputersCount)</span>")
            [void]$customerHtml.AppendLine("      <span class=""pill"">Reviewed User Accounts: $(ConvertTo-HtmlText $sourcePackage.UserReviewCount)</span>")
            [void]$customerHtml.AppendLine("      <span class=""pill"">Empty Groups: $(ConvertTo-HtmlText $sourcePackage.EmptyGroupsCount)</span>")
            [void]$customerHtml.AppendLine("      <span class=""pill"">Single-Member Groups: $(ConvertTo-HtmlText $sourcePackage.SingleMemberGroupsCount)</span>")
            [void]$customerHtml.AppendLine("      <span class=""pill"">Groups With Disabled/Inactive Members: $(ConvertTo-HtmlText $sourcePackage.DisabledInactiveGroupsCount)</span>")
            $customerFolder = "Reports/$($sourcePackage.Label)"
            [void]$customerHtml.AppendLine('      <ul>')
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/00-How-To-Review.txt"">Open the step-by-step review instructions for this environment</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/01-Include-Users.csv"">Open 01-Include-Users.csv</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/02-Include-Groups.csv"">Open 02-Include-Groups.csv</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/03-Include-Computers.csv"">Open 03-Include-Computers.csv</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/04-Excluded-Or-Needs-Review.csv"">Open 04-Excluded-Or-Needs-Review.csv</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/05-User-Review.csv"">Open 05-User-Review.csv</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/06-Empty-Groups.csv"">Open 06-Empty-Groups.csv</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/07-Single-Member-Groups.csv"">Open 07-Single-Member-Groups.csv</a></li>")
            [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/08-Groups-With-Disabled-Or-Inactive-Members.csv"">Open 08-Groups-With-Disabled-Or-Inactive-Members.csv</a></li>")
            if ($sourcePackage.DuplicatePath) {
                [void]$customerHtml.AppendLine("        <li><a href=""$(ConvertTo-HtmlText ($customerFolder -replace '\\','/'))/09-Duplicate-Conflicts.csv"">Open 09-Duplicate-Conflicts.csv</a></li>")
            }
            [void]$customerHtml.AppendLine('      </ul>')
        }
        [void]$customerHtml.AppendLine('    </div>')
        [void]$customerHtml.AppendLine('  </div>')
        [void]$customerHtml.AppendLine('</body>')
        [void]$customerHtml.AppendLine('</html>')
        $customerHtml.ToString() | Set-Content -LiteralPath $customerIndexPath -Encoding UTF8

        @(
            'Migration Planning Review Package',
            '',
            'Start here:',
            '1. Extract the full zip to a local folder.',
            '2. Open index.html in a web browser.',
            '3. Read the section titled "What We Need From You".',
            '4. Review each environment folder under Reports and fill in the CustomerDecision, Owner, Comment, and RequiredAction columns in the CSV files.',
            '',
            'What the files are for:',
            '- 01-Include-Users.csv: users currently proposed for migration',
            '- 02-Include-Groups.csv: groups currently proposed for migration',
            '- 03-Include-Computers.csv: computer accounts currently proposed for migration',
            '- 04-Excluded-Or-Needs-Review.csv: objects currently excluded or needing a scope decision',
            '- 05-User-Review.csv: user accounts needing special handling, such as service accounts, privileged accounts, or UPN changes',
            '- 06-Empty-Groups.csv: groups with no direct members',
            '- 07-Single-Member-Groups.csv: groups with exactly one direct member',
            '- 08-Groups-With-Disabled-Or-Inactive-Members.csv: groups containing disabled or inactive direct members',
            '- 09-Duplicate-Conflicts.csv: conflicts between source and target naming/identity, if present',
            '',
            'What we need back from you:',
            '- Which rows should stay in scope',
            '- Which rows should be removed from scope',
            '- Owners and business purpose for flagged user accounts',
            '- Cleanup or migration decisions for empty, single-member, and stale-member groups',
            '- Any rename, merge, defer, or exception decisions for duplicate conflicts',
            '',
            'Important:',
            '- Keep the folder structure intact so links continue to work.',
            '- If you edit the CSVs in Excel, save them with the same file names.',
            '- Please fill in the CustomerDecision, Owner, Comment, and RequiredAction columns directly in the CSV files.'
        ) | Set-Content -LiteralPath $customerReadmePath -Encoding UTF8

        if ($ZipCustomerPackage) {
            $customerZipPath = Join-Path $OutputRoot ("MigrationPlanning_{0}_{1}.zip" -f $safeCustomerName, $timestamp)
            if (Test-Path -LiteralPath $customerZipPath -PathType Leaf) {
                Remove-Item -LiteralPath $customerZipPath -Force
            }
            Compress-Archive -LiteralPath $customerPackageRoot -DestinationPath $customerZipPath -CompressionLevel Optimal -Force
        }
    }

    return [pscustomobject]@{
        OutputRoot        = $OutputRoot
        ManifestPath      = $manifestPath
        ReadmePath        = $readmePath
        PrerequisiteCsv   = $prereqs.CsvPath
        PrerequisiteJson  = $prereqs.JsonPath
        SourcePackages    = $sourcePackages.ToArray()
        HasTarget         = [bool]$TargetRunRoot
        CustomerPackageRoot = $customerPackageRoot
        CustomerIndexPath = $customerIndexPath
        CustomerReadmePath = $customerReadmePath
        CustomerChecklistPath = $customerChecklistPath
        CustomerZipPath = $customerZipPath
    }
}
