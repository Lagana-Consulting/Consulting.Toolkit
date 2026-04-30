function Test-AdMigrationPrerequisites {
    <#
    .SYNOPSIS
    Validate migration planning prerequisites from one or more discovery runs.

    .DESCRIPTION
    Produces a checklist-oriented summary for internal migration preparation. The
    output is intended for consultants, not customers, and highlights conditions
    that may affect migration sequencing, wave scope, and include/exclude logic.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SourceRunRoot,

        [string]$TargetRunRoot,

        [string]$OutputRoot,

        [string]$PlanningConfigPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $rules = Resolve-AdPlanningRules -PlanningConfigPath $PlanningConfigPath
    $timestamp = Get-AdPlanningTimestamp

    if ($OutputRoot -and -not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }

    $targetData = $null
    if (-not [string]::IsNullOrWhiteSpace($TargetRunRoot)) {
        $targetData = Get-AdPlanningRunData -RunRoot $TargetRunRoot
    }

    $allRows = New-Object System.Collections.Generic.List[object]
    $sourceResults = New-Object System.Collections.Generic.List[object]

    foreach ($sourcePath in @($SourceRunRoot)) {
        $sourceData = Get-AdPlanningRunData -RunRoot $sourcePath
        $summary = $sourceData.Summary
        $scopeName = $summary.ForestName

        $staleUsers = @(
            $sourceData.Users |
                Where-Object {
                    (ConvertTo-AdPlanningInt -Value $_.LastLogonDays -Default 0) -gt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.UserStaleDays -Default 180)
                }
        )
        $staleComputers = @(
            $sourceData.Computers |
                Where-Object {
                    (ConvertTo-AdPlanningInt -Value $_.LastLogonDays -Default 0) -gt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.ComputerStaleDays -Default 90)
                }
        )
        $summary.StaleUsersCount = $staleUsers.Count
        $summary.StaleComputersCount = $staleComputers.Count

        $weakPolicies = @(
            $sourceData.PasswordPolicies |
                Where-Object {
                    (-not (Test-AdPlanningBoolean $_.ComplexityEnabled)) -or
                    ((ConvertTo-AdPlanningInt -Value $_.MinPasswordLength -Default 0) -lt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.PreferredMinPasswordLength -Default 14)) -or
                    ((ConvertTo-AdPlanningInt -Value $_.MaxPasswordAgeDays -Default 0) -gt (ConvertTo-AdPlanningInt -Value $rules.Thresholds.PreferredMaxPasswordAgeDays -Default 180)) -or
                    ((ConvertTo-AdPlanningInt -Value $_.MaxPasswordAgeDays -Default 0) -eq 0)
                }
        )

        $privilegedSet = @($sourceData.PrivilegedAccounts | ForEach-Object { ([string]$_.SamAccountName).Trim().ToLowerInvariant() } | Sort-Object -Unique)
        $serviceSet = @($sourceData.ServiceAccounts | ForEach-Object { ([string]$_.SamAccountName).Trim().ToLowerInvariant() } | Sort-Object -Unique)
        $sourceUpnSuffixes = @($sourceData.UpnSuffixes | ForEach-Object { [string]$_.Suffix } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
        $targetUpnSuffixes = @()
        $sourceOnlyUpnSuffixes = @()
        $sourceOnlyMailDomains = @()
        $duplicateConflicts = @()

        if ($targetData) {
            $targetUpnSuffixes = @($targetData.UpnSuffixes | ForEach-Object { [string]$_.Suffix } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
            $sourceOnlyUpnSuffixes = @($sourceUpnSuffixes | Where-Object { $targetUpnSuffixes -notcontains $_ } | Sort-Object -Unique)
            $sourceOnlyMailDomains = @($sourceData.MailDomains | Where-Object { $targetData.MailDomains -notcontains $_ } | Sort-Object -Unique)
            $duplicateOutputRoot = if ($OutputRoot) { Join-Path $OutputRoot 'duplicates' } else { Join-Path $env:TEMP "AdPlanningDupes_$timestamp" }
            if (-not (Test-Path -LiteralPath $duplicateOutputRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $duplicateOutputRoot -Force | Out-Null
            }
            $duplicateConflicts = @(Invoke-AdPlanningDuplicateCheck -SourceRunRoot $sourcePath -TargetRunRoot $TargetRunRoot -OutputRoot $duplicateOutputRoot)
        }

        $rows = @(
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Info'; Status = 'Pass'; Check = 'Discovery output loaded'; Result = "Loaded $($summary.DomainCount) domain(s), $($summary.UsersTotal) users, $($summary.GroupsTotal) groups, and $($summary.ComputersTotal) computers."; Recommendation = 'Continue planning package generation.' }
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($staleUsers.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Stale user cleanup'; Result = "$($staleUsers.Count) user account(s) are older than $(ConvertTo-AdPlanningInt -Value $rules.Thresholds.UserStaleDays -Default 180) days since last logon."; Recommendation = 'Review stale users before adding them to default migration waves.' }
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($staleComputers.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Stale computer cleanup'; Result = "$($staleComputers.Count) computer object(s) are older than $(ConvertTo-AdPlanningInt -Value $rules.Thresholds.ComputerStaleDays -Default 90) days since last logon."; Recommendation = 'Remove or exclude stale computer objects from migration scope.' }
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($weakPolicies.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Password policy baseline'; Result = "$($weakPolicies.Count) default password policy row(s) fall outside the current planning baseline."; Recommendation = 'Document the password policy gap and decide whether remediation happens before or after migration.' }
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($summary.NonRoutableUpnCount -gt 0) { 'Warn' } else { 'Pass' }); Check = 'UPN suffix normalization'; Result = "$($summary.NonRoutableUpnCount) account(s) use non-routable UPN suffixes."; Recommendation = 'Plan UPN changes and namespace normalization before identity matching activities.' }
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($serviceSet.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Service account handling'; Result = "$($serviceSet.Count) service account candidate(s) were identified."; Recommendation = 'Move service accounts into dedicated review and migration waves with application-owner validation.' }
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($privilegedSet.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Privileged account handling'; Result = "$($privilegedSet.Count) privileged account(s) were identified."; Recommendation = 'Handle privileged identities in dedicated waves and verify delegated access requirements.' }
            [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($summary.TrustCount -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Trust dependency review'; Result = "$($summary.TrustCount) trust relationship(s) were discovered."; Recommendation = 'Validate authentication, name resolution, and dependency expectations for trusted domains.' }
        )

        if ($targetData) {
            $rows += @(
                [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($duplicateConflicts.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Identity conflicts vs target'; Result = "$($duplicateConflicts.Count) source-to-target identifier conflict(s) were detected."; Recommendation = 'Resolve or explicitly track duplicate identifiers before migration execution.' }
                [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($sourceOnlyUpnSuffixes.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Source-only UPN suffixes'; Result = if ($sourceOnlyUpnSuffixes.Count -gt 0) { $sourceOnlyUpnSuffixes -join ', ' } else { 'No source-only suffixes detected.' }; Recommendation = 'Add or remap source UPN suffixes in the target namespace plan.' }
                [pscustomobject]@{ Scope = $scopeName; Severity = 'Warning'; Status = $(if ($sourceOnlyMailDomains.Count -gt 0) { 'Warn' } else { 'Pass' }); Check = 'Source-only SMTP domains'; Result = if ($sourceOnlyMailDomains.Count -gt 0) { $sourceOnlyMailDomains -join ', ' } else { 'No source-only SMTP domains detected.' }; Recommendation = 'Validate accepted domains, routing, and target namespace ownership for source-only SMTP domains.' }
            )
        }

        foreach ($row in $rows) { [void]$allRows.Add($row) }

        [void]$sourceResults.Add([pscustomobject]@{
            SourceRunRoot        = $sourcePath
            ForestName           = $scopeName
            StaleUsersCount      = $staleUsers.Count
            StaleComputersCount  = $staleComputers.Count
            WeakPolicyCount      = $weakPolicies.Count
            NonRoutableUpnCount  = $summary.NonRoutableUpnCount
            ServiceAccountCount  = $serviceSet.Count
            PrivilegedCount      = $privilegedSet.Count
            TrustCount           = $summary.TrustCount
            DuplicateConflictCount = $duplicateConflicts.Count
        })
    }

    $rowsArray = $allRows.ToArray()
    $sourcesArray = $sourceResults.ToArray()

    $csvPath = $null
    $jsonPath = $null
    if ($OutputRoot) {
        $csvPath = Join-Path $OutputRoot "AD__Migration__Prerequisites__Summary__$timestamp.csv"
        $jsonPath = Join-Path $OutputRoot "AD__Migration__Prerequisites__Summary__$timestamp.json"
        @($rowsArray) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Force
        [pscustomobject]@{
            GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            SourceRunRoot  = @($SourceRunRoot)
            TargetRunRoot  = $TargetRunRoot
            Rows           = @($rowsArray)
            Sources        = @($sourcesArray)
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    }

    return [pscustomobject]@{
        CsvPath        = $csvPath
        JsonPath       = $jsonPath
        Rows           = @($rowsArray)
        Sources        = @($sourcesArray)
        WarningCount   = @($rowsArray | Where-Object { $_.Status -eq 'Warn' }).Count
        FailureCount   = @($rowsArray | Where-Object { $_.Status -eq 'Fail' }).Count
    }
}
