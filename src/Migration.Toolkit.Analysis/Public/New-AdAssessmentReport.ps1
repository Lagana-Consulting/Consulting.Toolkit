function New-AdAssessmentReport {
    <#
    .SYNOPSIS
    Generates executive-level HTML assessment report from AD discovery data.

    .DESCRIPTION
    Creates a professional executive summary HTML report from discovery CSVs.
    Focuses on high-level metrics, risk indicators, and recommendations suitable
    for stakeholder presentations.

    Report sections:
    - Executive summary dashboard
    - Key metrics (user/group/computer counts, stale percentages)
    - Risk overview (privileged accounts, encryption, SID history)
    - Per-domain summary tables
    - Top migration risks and remediation steps

    Lighter-weight alternative to New-AdComprehensiveAssessmentReport.

    .PARAMETER DiscoveryOutputPath
    Path to discovery output folder containing CSV files and domain subfolders.
    Must contain:
    - Assessment summary CSV (root or 00_schemas/)
    - Migration risk flags CSV
    - Domain summary CSVs in 20_domains/

    .PARAMETER OutputPath
    Path where HTML report will be saved.
    If not specified, creates report in discovery root with timestamp:
    AD__Assessment__Report_{timestamp}.html

    .EXAMPLE
    New-AdAssessmentReport -DiscoveryOutputPath "C:\Discovery\ADOnly_20260128-100000"

    Generates report with auto-generated filename in discovery folder.

    .EXAMPLE
    New-AdAssessmentReport `
      -DiscoveryOutputPath "C:\Discovery\Latest" `
      -OutputPath "C:\Reports\Executive_Summary.html"

    Generates report at specified location.

    .EXAMPLE
    $reportPath = New-AdAssessmentReport -DiscoveryOutputPath $discoveryPath
    Start-Process $reportPath

    Generates report and opens it in browser.

    .OUTPUTS
    None. Creates HTML file at OutputPath (or auto-generated path in discovery folder).

    .NOTES
    Requires PowerShell 7+ (Analysis module).
    Falls back gracefully if assessment summary CSV is missing (builds from domain data).
    Suitable for quick stakeholder briefings and migration kickoff presentations.

    .LINK
    New-AdComprehensiveAssessmentReport
    Invoke-AdDiscoveryAnalysis
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$DiscoveryOutputPath,

        [ValidateScript({ -not $_ -or (Test-Path $_ -PathType Container) })]
        [string]$TargetRunRoot,

        [string]$ExecutiveSummaryConfigPath,

        [string]$OutputPath
    )

    # Default output to discovery root with timestamp
    if (-not $OutputPath) {
        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $OutputPath = Join-Path $DiscoveryOutputPath "AD__Assessment__Report__$timestamp.html"
    }

    $runData = Get-AdDiscoveryRunSummary -RunRoot $DiscoveryOutputPath
    $summary = $runData.Summary
    $riskSummary = @($runData.RiskSummary)
    $domainSummaries = @($runData.DomainSummaries)
    $domainFolders = @($runData.DomainFolders)

    function ConvertTo-AdFindingSlug {
        param([string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) { return 'finding' }

        $slug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
        if ([string]::IsNullOrWhiteSpace($slug)) { return 'finding' }
        return $slug
    }

    function New-AdFindingEvidence {
        param(
            [Parameter(Mandatory)][string]$Key,
            [Parameter(Mandatory)][string]$Title,
            [Parameter(Mandatory)][string]$SourceSummary,
            [Parameter(Mandatory)][string]$EvidenceSummary,
            [AllowEmptyCollection()][array]$Rows = @()
        )

        [pscustomobject]@{
            Key             = $Key
            Anchor          = "evidence-$(ConvertTo-AdFindingSlug $Key)"
            Title           = $Title
            SourceSummary   = $SourceSummary
            EvidenceSummary = $EvidenceSummary
            Rows            = @($Rows)
            CsvPath         = $null
            RelativeCsvPath = $null
            RowCount        = @($Rows).Count
        }
    }

    function ConvertTo-AdConfigMap {
        param([AllowNull()][object]$Object)

        $map = @{}
        if ($null -eq $Object) { return $map }
        foreach ($property in $Object.PSObject.Properties) {
            $map[$property.Name] = $property.Value
        }
        return $map
    }

    function Test-AdConfigObject {
        param([AllowNull()][object]$Value)

        if ($null -eq $Value) { return $false }
        if ($Value -is [string] -or $Value -is [ValueType]) { return $false }
        if ($Value -is [System.Collections.IDictionary]) { return $true }
        if ($Value -is [System.Collections.IEnumerable]) { return $false }

        return $Value.GetType().Name -eq 'PSCustomObject'
    }

    function Merge-AdConfigMaps {
        param(
            [AllowNull()][object]$Base,
            [AllowNull()][object]$Override
        )

        $result = ConvertTo-AdConfigMap $Base
        $overrideMap = ConvertTo-AdConfigMap $Override

        foreach ($key in $overrideMap.Keys) {
            $baseValue = if ($result.ContainsKey($key)) { $result[$key] } else { $null }
            $overrideValue = $overrideMap[$key]

            $baseIsObject = Test-AdConfigObject $baseValue
            $overrideIsObject = Test-AdConfigObject $overrideValue

            if ($baseIsObject -and $overrideIsObject) {
                $result[$key] = [pscustomobject](Merge-AdConfigMaps -Base $baseValue -Override $overrideValue)
            }
            else {
                $result[$key] = $overrideValue
            }
        }

        return $result
    }

    function ConvertTo-HtmlText {
        param([AllowNull()][object]$Value)

        if ($null -eq $Value) { return '' }
        return [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }

    function ConvertTo-AdDisplayBool {
        param([AllowNull()][object]$Value)

        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'Unknown' }
        if (Test-AdAnalysisBoolean $Value) { return 'Yes' }
        return 'No'
    }

    function Get-AdMailDomains {
        param([AllowEmptyCollection()][array]$Records)

        $domains = New-Object System.Collections.Generic.List[string]

        foreach ($record in @($Records)) {
            $mail = [string]$record.Mail
            if ([string]::IsNullOrWhiteSpace($mail) -or $mail -notmatch '@') { continue }

            $domain = ($mail.Split('@')[-1]).Trim().ToLowerInvariant()
            if (-not [string]::IsNullOrWhiteSpace($domain) -and -not $domains.Contains($domain)) {
                $domains.Add($domain)
            }
        }

        return @($domains | Sort-Object)
    }

    function Resolve-AdExecutiveSummaryConfig {
        param(
            [string]$ExplicitPath,
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][string]$ForestName
        )

        $candidatePaths = New-Object System.Collections.Generic.List[string]
        if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
            if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
                throw "Executive summary config not found: $ExplicitPath"
            }
            $candidatePaths.Add($ExplicitPath)
        }
        else {
            $candidatePaths.Add((Join-Path $RunRoot '99_manifest\ExecutiveSummary.Config.json'))
            $candidatePaths.Add((Join-Path $RunRoot 'ExecutiveSummary.Config.json'))
        }

        $rawConfig = $null
        foreach ($candidate in $candidatePaths) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $rawConfig = Get-Content -LiteralPath $candidate -Raw | ConvertFrom-Json
                break
            }
        }

        if (-not $rawConfig) { return $null }

        $defaults = if ($rawConfig.PSObject.Properties['Defaults']) { $rawConfig.Defaults } else { $rawConfig }
        $perForest = if ($rawConfig.PSObject.Properties['PerForest']) { $rawConfig.PerForest } else { $null }
        $forestOverride = $null
        if ($perForest -and $perForest.PSObject.Properties[$ForestName]) {
            $forestOverride = $perForest.$ForestName
        }

        $merged = Merge-AdConfigMaps -Base $defaults -Override $forestOverride
        if ($merged.Keys.Count -eq 0) { return $null }
        return [pscustomobject]$merged
    }

    $reportDirectory = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }

    $executiveSummaryConfig = Resolve-AdExecutiveSummaryConfig -ExplicitPath $ExecutiveSummaryConfigPath -RunRoot $DiscoveryOutputPath -ForestName $summary.ForestName
    $targetSummary = $null
    $duplicateConflicts = @()
    if (-not [string]::IsNullOrWhiteSpace($TargetRunRoot)) {
        $targetSummary = (Get-AdDiscoveryRunSummary -RunRoot $TargetRunRoot).Summary
        $duplicateConflicts = @(
            Invoke-AdCrossForestDuplicateCheck `
                -SourceRunRoots @($DiscoveryOutputPath) `
                -TargetRunRoot $TargetRunRoot `
                -OutputRoot $reportDirectory `
                -PassThru
        )
    }

    $reportBaseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
    $evidenceFolderName = "${reportBaseName}_evidence"
    $evidenceRoot = Join-Path $reportDirectory $evidenceFolderName

    $forestSummaryRaw = Import-AdAnalysisCsvSafe -Path (Join-Path $DiscoveryOutputPath '10_forest\AD__Forest__Summary__Forest.csv') | Select-Object -First 1
    $trustRows = @($runData.Trusts)
    $siteRows = @($runData.Sites)
    $siteLinkRows = @($runData.SiteLinks)
    $upnSuffixRows = @($runData.UpnSuffixes)
    $adcsEnterpriseCas = @(Import-AdAnalysisCsvSafe -Path (Join-Path $DiscoveryOutputPath '10_forest\AD__Forest__Security__ADCS__EnterpriseCAs__Forest.csv'))

    $allUsers = @()
    $allGroups = @()
    $allComputers = @()
    $allContacts = @()
    $allSpns = @()
    $allPublishedSharedFolders = @()
    $allPublishedPrinters = @()
    $allDomainControllers = @()
    $allDomainSummaryRows = @()
    $allFgppPolicies = @()
    $allGpos = @()
    $allGpoLinks = @()
    $allGpoDelegation = @()
    $allAdminCountObjects = @()
    $allAdminSdHolder = @()
    $allDefaultPasswordPolicies = @()
    $allServiceAccountCandidates = @()
    $allPrivilegedAccounts = @()

    foreach ($folder in $domainFolders) {
        $users = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__Users__*.csv'))
        $groups = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__Groups__*.csv'))
        $computers = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__ComputersAll__*.csv'))
        $contacts = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__Contacts__*.csv'))
        $spns = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__Spns__*.csv', '*__Identity__SPNs__*.csv'))
        $publishedSharedFolders = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Inventory__PublishedSharedFolders__*.csv'))
        $publishedPrinters = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Inventory__PublishedPrinters__*.csv'))
        $domainControllers = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Infrastructure__DomainControllers__*.csv'))
        $domainSummaryRows = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Summary__Domain-*.csv') | Select-Object -First 1)
        $adminSdHolder = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__AdminSdHolderImpact__*.csv'))
        $adminCountObjects = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__AdminCountObjects__*.csv'))
        $defaultPolicy = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__PasswordPolicyDefault__*.csv') | Select-Object -First 1)
        $fgppPolicies = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__PasswordPolicyFgpp__*.csv'))
        $serviceAccountCandidates = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Identity__ServiceAccountCandidates__*.csv'))
        $privilegedAccounts = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__Security__PrivilegedAccounts__*.csv'))
        $gpos = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__GPO__Inventory__*.csv'))
        $gpoLinks = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__GPO__Links__*.csv'))
        $gpoDelegation = @(Get-AdDiscoveryFirstCsv -Directory $folder.FullName -Patterns @('*__GPO__Delegation__*.csv'))

        if ($users) { $allUsers += $users }
        if ($groups) { $allGroups += $groups }
        if ($computers) { $allComputers += $computers }
        if ($contacts) { $allContacts += $contacts }
        if ($spns) { $allSpns += $spns }
        if ($publishedSharedFolders) { $allPublishedSharedFolders += $publishedSharedFolders }
        if ($publishedPrinters) { $allPublishedPrinters += $publishedPrinters }
        if ($domainControllers) { $allDomainControllers += $domainControllers }
        if ($domainSummaryRows) { $allDomainSummaryRows += $domainSummaryRows }
        if ($adminSdHolder) { $allAdminSdHolder += $adminSdHolder }
        if ($adminCountObjects) { $allAdminCountObjects += $adminCountObjects }
        if ($defaultPolicy) { $allDefaultPasswordPolicies += $defaultPolicy }
        if ($fgppPolicies) { $allFgppPolicies += $fgppPolicies }
        if ($serviceAccountCandidates) { $allServiceAccountCandidates += $serviceAccountCandidates }
        if ($privilegedAccounts) { $allPrivilegedAccounts += $privilegedAccounts }
        if ($gpos) { $allGpos += $gpos }
        if ($gpoLinks) { $allGpoLinks += $gpoLinks }
        if ($gpoDelegation) { $allGpoDelegation += $gpoDelegation }
    }

    $sourceMailDomains = @(Get-AdMailDomains -Records (@($allUsers) + @($allGroups) + @($allContacts)))
    $targetUpnSuffixRows = @()
    $targetMailDomains = @()
    $targetForestSummaryRaw = $null

    if (-not [string]::IsNullOrWhiteSpace($TargetRunRoot)) {
        $targetForestSummaryRaw = Import-AdAnalysisCsvSafe -Path (Join-Path $TargetRunRoot '10_forest\AD__Forest__Summary__Forest.csv') | Select-Object -First 1
        $targetUpnSuffixRows = @(Import-AdAnalysisCsvSafe -Path (Join-Path $TargetRunRoot '10_forest\AD__Forest__Identity__UpnSuffixes__Forest.csv'))

        $targetDomainFolders = @(Get-AdDiscoveryDomainFolders -RunRoot $TargetRunRoot)
        $targetUsers = @()
        $targetGroups = @()
        $targetContacts = @()
        foreach ($targetFolder in $targetDomainFolders) {
            $targetUsers += @(Get-AdDiscoveryFirstCsv -Directory $targetFolder.FullName -Patterns @('*__Identity__Users__*.csv'))
            $targetGroups += @(Get-AdDiscoveryFirstCsv -Directory $targetFolder.FullName -Patterns @('*__Identity__Groups__*.csv'))
            $targetContacts += @(Get-AdDiscoveryFirstCsv -Directory $targetFolder.FullName -Patterns @('*__Identity__Contacts__*.csv'))
        }

        $targetMailDomains = @(Get-AdMailDomains -Records (@($targetUsers) + @($targetGroups) + @($targetContacts)))
    }

    $staleUserEvidenceRows = @(
        $allUsers |
            Where-Object {
                $days = ConvertTo-AdAnalysisNumber $_.LastLogonDays
                $null -ne $days -and $days -gt 180
            } |
            Select-Object DomainFqdn, SamAccountName, Name, UserPrincipalName, Enabled, LastLogonDays, PasswordAgeDays, DistinguishedName, Description
    )

    $staleComputerEvidenceRows = @(
        $allComputers |
            Where-Object {
                $days = ConvertTo-AdAnalysisNumber $_.LastLogonDays
                $null -ne $days -and $days -gt 90
            } |
            Select-Object DomainFqdn, Name, SamAccountName, DnsHostName, Enabled, IsServer, OperatingSystem, LastLogonDays, DistinguishedName, Description
    )

    $kerberosEvidenceRows = @(
        @(
            @($allUsers | Select-Object @{ Name = 'ObjectClass'; Expression = { 'user' } }, DomainFqdn, SamAccountName, Name, UserPrincipalName, Enabled, EncryptionTypes, EncryptionRisk, DistinguishedName) +
            @($allComputers | Select-Object @{ Name = 'ObjectClass'; Expression = { 'computer' } }, DomainFqdn, SamAccountName, Name, DnsHostName, Enabled, EncryptionTypes, EncryptionRisk, DistinguishedName)
        ) | Where-Object {
            $risk = [string]$_.EncryptionRisk
            $types = [string]$_.EncryptionTypes
            $risk -match 'RC4|NoAES|High' -and $types -notmatch 'AES'
        }
    )

    $weakPasswordPolicyEvidenceRows = @(
        $allDefaultPasswordPolicies |
            ForEach-Object {
                $weaknesses = New-Object System.Collections.Generic.List[string]

                if (-not (Test-AdAnalysisBoolean $_.ComplexityEnabled)) {
                    $weaknesses.Add('Complexity disabled')
                }

                $minLength = ConvertTo-AdAnalysisNumber $_.MinPasswordLength
                if ($null -eq $minLength -or $minLength -lt 12) {
                    $weaknesses.Add("Min password length below 12 ($minLength)")
                }

                $maxAge = ConvertTo-AdAnalysisNumber $_.MaxPasswordAgeDays
                if ($null -eq $maxAge -or $maxAge -eq 0 -or $maxAge -gt 90) {
                    $weaknesses.Add("Max password age not in 1-90 days ($maxAge)")
                }

                $lockoutThreshold = ConvertTo-AdAnalysisNumber $_.LockoutThreshold
                if ($null -eq $lockoutThreshold -or $lockoutThreshold -le 0) {
                    $weaknesses.Add("Lockout threshold missing or disabled ($lockoutThreshold)")
                }

                if (Test-AdAnalysisBoolean $_.ReversibleEncryptionEnabled) {
                    $weaknesses.Add('Reversible encryption enabled')
                }

                if ($weaknesses.Count -gt 0) {
                    [pscustomobject]@{
                        DomainFqdn                  = $_.DomainFqdn
                        PolicyType                  = 'Default Domain Policy'
                        ComplexityEnabled           = $_.ComplexityEnabled
                        MinPasswordLength           = $_.MinPasswordLength
                        PasswordHistoryCount        = $_.PasswordHistoryCount
                        MinPasswordAgeDays          = $_.MinPasswordAgeDays
                        MaxPasswordAgeDays          = $_.MaxPasswordAgeDays
                        LockoutThreshold            = $_.LockoutThreshold
                        ReversibleEncryptionEnabled = $_.ReversibleEncryptionEnabled
                        Weaknesses                  = ($weaknesses -join '; ')
                    }
                }
            }
    )

    $sidHistoryEvidenceRows = @(
        $allUsers |
            Where-Object {
                $count = ConvertTo-AdAnalysisNumber $_.SidHistoryCount
                $null -ne $count -and $count -gt 0
            } |
            Select-Object DomainFqdn, SamAccountName, Name, UserPrincipalName, SidHistoryCount, Enabled, DistinguishedName
    )

    $adminSdHolderEvidenceRows = @(
        $allAdminSdHolder |
            Select-Object DomainFqdn, ObjectClass, Name, AdminCount, Impact, DistinguishedName, WhenChanged
    )

    $serviceAccountEvidenceRows = @(
        $allServiceAccountCandidates |
            Select-Object DomainFqdn, SamAccountName, Name, Enabled, HeuristicFlags, PasswordAgeDays, LastLogonDays, Description, DistinguishedName
    )

    $privilegedAccountEvidenceRows = @(
        $allPrivilegedAccounts |
            Select-Object DomainFqdn, SamAccountName, Name, Enabled, AdminCount, InPrivGroups, PrivGroups, PasswordAgeDays, LastLogonDays, DistinguishedName
    )

    $expiredPasswordEvidenceRows = @(
        $allUsers |
            Where-Object {
                $age = ConvertTo-AdAnalysisNumber $_.PasswordAgeDays
                $null -ne $age -and $age -gt 365
            } |
            Select-Object DomainFqdn, SamAccountName, Name, UserPrincipalName, Enabled, PasswordAgeDays, PasswordLastSetUtc, LastLogonDays, DistinguishedName
    )

    $nonRoutableUpnEvidenceRows = @(
        $allUsers |
            Where-Object { Test-AdAnalysisBoolean $_.IsNonRoutableUpnSuffix } |
            Select-Object DomainFqdn, SamAccountName, Name, UserPrincipalName, UPNSuffix, IsKnownUpnSuffix, IsNonRoutableUpnSuffix, Enabled, DistinguishedName
    )

    $findingEvidence = @{}
    $findingEvidence['stale-users'] = New-AdFindingEvidence -Key 'stale-users' -Title 'Stale User Accounts Evidence' -SourceSummary 'Source dataset: AD__Domain__Identity__Users__*.csv filtered to LastLogonDays > 180.' -EvidenceSummary 'Affected user accounts exported for review.' -Rows $staleUserEvidenceRows
    $findingEvidence['stale-computers'] = New-AdFindingEvidence -Key 'stale-computers' -Title 'Stale Computer Accounts Evidence' -SourceSummary 'Source dataset: AD__Domain__Identity__ComputersAll__*.csv filtered to LastLogonDays > 90.' -EvidenceSummary 'Affected workstation and server computer accounts exported for review.' -Rows $staleComputerEvidenceRows
    $findingEvidence['weak-kerberos'] = New-AdFindingEvidence -Key 'weak-kerberos' -Title 'Weak Kerberos and RC4-Only Evidence' -SourceSummary 'Source datasets: users and computers filtered to objects without AES support.' -EvidenceSummary 'Objects that appear to rely on RC4 or otherwise lack AES support exported for review.' -Rows $kerberosEvidenceRows
    $findingEvidence['weak-password-policy'] = New-AdFindingEvidence -Key 'weak-password-policy' -Title 'Weak Password Policy Evidence' -SourceSummary 'Source dataset: AD__Domain__Security__PasswordPolicyDefault__*.csv evaluated against toolkit baseline rules.' -EvidenceSummary 'Default domain password policies with weak settings exported for review.' -Rows $weakPasswordPolicyEvidenceRows
    $findingEvidence['sid-history'] = New-AdFindingEvidence -Key 'sid-history' -Title 'SID History Evidence' -SourceSummary 'Source dataset: AD__Domain__Identity__Users__*.csv filtered to SidHistoryCount > 0.' -EvidenceSummary 'User accounts with SID history exported for review.' -Rows $sidHistoryEvidenceRows
    $findingEvidence['adminsdholder'] = New-AdFindingEvidence -Key 'adminsdholder' -Title 'AdminSDHolder Protected Accounts Evidence' -SourceSummary 'Source dataset: AD__Domain__Security__AdminSdHolderImpact__*.csv.' -EvidenceSummary 'Protected users and groups exported for review.' -Rows $adminSdHolderEvidenceRows
    $findingEvidence['service-account-candidates'] = New-AdFindingEvidence -Key 'service-account-candidates' -Title 'Service Account Candidate Evidence' -SourceSummary 'Source dataset: AD__Domain__Identity__ServiceAccountCandidates__*.csv.' -EvidenceSummary 'Potential service accounts requiring application-owner review exported for validation.' -Rows $serviceAccountEvidenceRows
    $findingEvidence['privileged-accounts'] = New-AdFindingEvidence -Key 'privileged-accounts' -Title 'Privileged Account Evidence' -SourceSummary 'Source dataset: AD__Domain__Security__PrivilegedAccounts__*.csv.' -EvidenceSummary 'Privileged accounts and group memberships exported for review.' -Rows $privilegedAccountEvidenceRows
    $findingEvidence['expired-password-age'] = New-AdFindingEvidence -Key 'expired-password-age' -Title 'Expired Password Age Evidence' -SourceSummary 'Source dataset: AD__Domain__Identity__Users__*.csv filtered to PasswordAgeDays > 365.' -EvidenceSummary 'User accounts with aged passwords exported for review.' -Rows $expiredPasswordEvidenceRows
    $findingEvidence['non-routable-upn'] = New-AdFindingEvidence -Key 'non-routable-upn' -Title 'Non-Routable UPN Evidence' -SourceSummary 'Source dataset: AD__Domain__Identity__Users__*.csv filtered to IsNonRoutableUpnSuffix = True.' -EvidenceSummary 'Affected accounts exported for review.' -Rows $nonRoutableUpnEvidenceRows

    # Parse risk categories from summary data (Flag, ObjectClass, Count)
    # High-risk flags: PasswordAgeOver365d, StaleLastLogonOver180d, Kerberos_NoAES, UPN_NonRoutableSuffix
    $riskCounts = @{
        Critical = 0
        High     = 0
        Medium   = 0
        Low      = 0
    }

    foreach ($item in $riskSummary) {
        # Handle missing or null Count property
        $count = if ($null -ne $item.Count) { [int]$item.Count } else { 0 }
        $flagName = $item.Flag

        $severity = if ($item.PSObject.Properties['Severity']) { [string]$item.Severity } else { '' }

        switch -Regex ($severity) {
            '^Critical$' { $riskCounts.Critical += $count; break }
            '^High$' { $riskCounts.High += $count; break }
            '^Medium$' { $riskCounts.Medium += $count; break }
            '^Low$' { $riskCounts.Low += $count; break }
            default {
                if ($flagName -match 'PasswordAgeOver365d|StaleLastLogonOver180d|Kerberos_NoAES|WeakPasswordPolicy|AdminSDHolderProtected|UnconstrainedDelegation|AsrepRoastableUsers') {
                    $riskCounts.High += $count
                } elseif ($flagName -match 'UPN_NonRoutableSuffix|UPN_SuffixNotInForestList|SIDHistoryPresent|ComputerStaleLastLogonOver90d') {
                    $riskCounts.Medium += $count
                } else {
                    $riskCounts.Low += $count
                }
            }
        }
    }

    $duplicateConflictCount = @($duplicateConflicts).Count

    # Calculate migration readiness score
    $readinessScore = 100
    $readinessScore -= [math]::Min(20, [math]::Ceiling($duplicateConflictCount / 5.0) * 2)
    $readinessScore -= [math]::Min(15, [int]$summary.WeakPasswordPoliciesCount * 10)
    $readinessScore -= [math]::Min(12, [math]::Ceiling([int]$summary.UsersNonRoutableUPNCount / 25.0) * 3)
    $readinessScore -= [math]::Min(10, [math]::Ceiling([int]$summary.ServiceAccountCandidatesCount / 10.0) * 2)
    $readinessScore -= [math]::Min(10, [math]::Ceiling([int]$summary.PrivilegedAccountsCount / 25.0) * 2)
    $readinessScore -= [math]::Min(10, [math]::Ceiling(([int]$summary.UsersStaleCount + [int]$summary.ComputersStaleCount) / 25.0) * 2)
    $readinessScore -= [math]::Min(8, ([int]$summary.UnconstrainedDelegationCount * 4) + ([int]$summary.AsrepRoastableUsersCount * 2))
    $readinessScore -= [math]::Min(8, [math]::Ceiling([int]$summary.ObjectsRC4OnlyCount / 25.0) * 2)
    $readinessScore -= [math]::Min(5, [math]::Max(0, [int]$summary.TrustCount - 1) * 2)
    $readinessScore = [math]::Max(0, $readinessScore)

    $readinessStatus = if ($readinessScore -ge 80) { 'Green' }
    elseif ($readinessScore -ge 60) { 'Amber' }
    else { 'Red' }

    if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['ReadinessOverride'] -and $executiveSummaryConfig.ReadinessOverride) {
        if ($executiveSummaryConfig.ReadinessOverride.PSObject.Properties['Score'] -and $null -ne $executiveSummaryConfig.ReadinessOverride.Score) {
            $readinessScore = [int]$executiveSummaryConfig.ReadinessOverride.Score
        }
        if ($executiveSummaryConfig.ReadinessOverride.PSObject.Properties['Status'] -and -not [string]::IsNullOrWhiteSpace([string]$executiveSummaryConfig.ReadinessOverride.Status)) {
            $readinessStatus = [string]$executiveSummaryConfig.ReadinessOverride.Status
        }
    }

    $readinessCssClass = switch -Regex ($readinessStatus.ToLowerInvariant()) {
        '^green|healthy$' { 'green'; break }
        '^amber|yellow|caution$' { 'amber'; break }
        default { 'red' }
    }

    $healthScore = $readinessScore
    $healthStatus = $readinessStatus

    $scopeLines = New-Object System.Collections.Generic.List[string]
    $scopeLines.Add("Source forest: $($summary.ForestName)")
    if ($targetSummary) {
        $scopeLines.Add("Target forest: $($targetSummary.ForestName)")
        $scopeLines.Add("Target domain count: $([int]$targetSummary.DomainsCount)")
    }
    $scopeLines.Add("Domains in scope: $([int]$summary.DomainsCount)")
    $scopeLines.Add("Objects discovered: $([int]$summary.UsersTotal) users, $([int]$summary.GroupsTotal) groups, $([int]$summary.ComputersTotal) devices")
    $scopeLines.Add("Dependencies identified: $([int]$summary.TrustCount) trust(s), $([int]$summary.ServiceAccountCandidatesCount) service account candidate(s), $([int]$summary.PrivilegedAccountsCount) privileged account(s), $([int]$summary.GpoCount) GPOs, $([int]$summary.OuCount) OUs")
    if ([int]$summary.AdcsEnterpriseCaCount -gt 0) {
        $scopeLines.Add("PKI dependencies: $([int]$summary.AdcsEnterpriseCaCount) enterprise CA instance(s)")
    }
    if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['ScopeNote'] -and -not [string]::IsNullOrWhiteSpace([string]$executiveSummaryConfig.ScopeNote)) {
        $scopeLines.Add([string]$executiveSummaryConfig.ScopeNote)
    }

    $riskLines = New-Object System.Collections.Generic.List[string]
    if ($duplicateConflictCount -gt 0) {
        $riskLines.Add("$duplicateConflictCount duplicate identity conflict(s) were detected between source and target and should be resolved before migration.")
    }
    if ([int]$summary.UsersNonRoutableUPNCount -gt 0) {
        $riskLines.Add("$([int]$summary.UsersNonRoutableUPNCount) account(s) use non-routable UPN suffixes, creating identity normalization risk.")
    }
    if ([int]$summary.ObjectsRC4OnlyCount -gt 0) {
        $riskLines.Add("$([int]$summary.ObjectsRC4OnlyCount) object(s) appear to rely on legacy or non-AES Kerberos settings.")
    }
    if ([int]$summary.ServiceAccountCandidatesCount -gt 0) {
        $riskLines.Add("$([int]$summary.ServiceAccountCandidatesCount) service account candidate(s) may require application-owner coordination and special cutover handling.")
    }
    if ([int]$summary.TrustCount -gt 0) {
        $riskLines.Add("$([int]$summary.TrustCount) trust relationship(s) may influence dependency analysis, authentication, and migration sequencing.")
    }
    if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['DnsOverlapAssessment'] -and -not [string]::IsNullOrWhiteSpace([string]$executiveSummaryConfig.DnsOverlapAssessment)) {
        $riskLines.Add("Namespace / DNS overlap assessment: $([string]$executiveSummaryConfig.DnsOverlapAssessment)")
    }
    else {
        $riskLines.Add('Namespace / DNS overlap was not automatically assessed in this discovery set and should be validated during migration planning.')
    }
    if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['AdditionalRisks'] -and $executiveSummaryConfig.AdditionalRisks) {
        foreach ($risk in @($executiveSummaryConfig.AdditionalRisks)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$risk)) { $riskLines.Add([string]$risk) }
        }
    }

    $recommendedTool = $null
    $recommendedCadence = $null
    $recommendedApproachNote = $null
    if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['RecommendedMigrationApproach'] -and $executiveSummaryConfig.RecommendedMigrationApproach) {
        $approachConfig = $executiveSummaryConfig.RecommendedMigrationApproach
        if ($approachConfig.PSObject.Properties['DirectoryMigrationTool']) { $recommendedTool = [string]$approachConfig.DirectoryMigrationTool }
        if ($approachConfig.PSObject.Properties['MigrationCadence']) { $recommendedCadence = [string]$approachConfig.MigrationCadence }
        if ($approachConfig.PSObject.Properties['Notes']) { $recommendedApproachNote = [string]$approachConfig.Notes }
    }

    if ([string]::IsNullOrWhiteSpace($recommendedTool)) {
        if ($targetSummary) {
            $recommendedTool = if ([string]$summary.ForestName -ne [string]$targetSummary.ForestName) { 'ADMT inter-forest' } else { 'ADMT intra-forest' }
        }
        else {
            $recommendedTool = 'Consultant confirmation required'
        }
    }

    if ([string]::IsNullOrWhiteSpace($recommendedCadence)) {
        $recommendStaged = $duplicateConflictCount -gt 0 -or
            [int]$summary.ServiceAccountCandidatesCount -gt 0 -or
            [int]$summary.PrivilegedAccountsCount -gt 10 -or
            [int]$summary.TrustCount -gt 0 -or
            [int]$summary.UsersTotal -gt 250 -or
            [int]$summary.ComputersTotal -gt 150

        $recommendedCadence = if ($recommendStaged) { 'Staged' } else { 'Big bang may be feasible for this scope' }
    }

    $hybridIdentityConsideration = if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['HybridIdentityConsiderations'] -and -not [string]::IsNullOrWhiteSpace([string]$executiveSummaryConfig.HybridIdentityConsiderations)) {
        [string]$executiveSummaryConfig.HybridIdentityConsiderations
    }
    else {
        'Hybrid identity was not directly assessed in this AD-only discovery run. Confirm Entra Connect, Cloud Sync, federation, and target tenant assumptions separately.'
    }

    $approachLines = New-Object System.Collections.Generic.List[string]
    $approachLines.Add("Directory migration approach: $recommendedTool")
    $approachLines.Add("Migration cadence: $recommendedCadence")
    $approachLines.Add("Hybrid identity considerations: $hybridIdentityConsideration")
    if (-not [string]::IsNullOrWhiteSpace($recommendedApproachNote)) {
        $approachLines.Add($recommendedApproachNote)
    }

    $complexityLines = New-Object System.Collections.Generic.List[string]
    if ([int]$summary.UsersTotal -gt 0 -or [int]$summary.ComputersTotal -gt 0) {
        $complexityLines.Add("Object volume: $([int]$summary.UsersTotal) users and $([int]$summary.ComputersTotal) devices are in scope.")
    }
    if ([int]$summary.TrustCount -gt 0 -or [int]$summary.DomainsCount -gt 1) {
        $complexityLines.Add("Topology: $([int]$summary.DomainsCount) domain(s) and $([int]$summary.TrustCount) trust relationship(s) require sequencing and validation.")
    }
    if ([int]$summary.ServiceAccountCandidatesCount -gt 0) {
        $complexityLines.Add("Application dependencies: $([int]$summary.ServiceAccountCandidatesCount) service account candidate(s) may need application-owner engagement.")
    }
    if ([int]$summary.PrivilegedAccountsCount -gt 0 -or [int]$summary.AdminSdHolderImpactCount -gt 0) {
        $complexityLines.Add("Privileged access: $([int]$summary.PrivilegedAccountsCount) privileged account(s) and $([int]$summary.AdminSdHolderImpactCount) protected object(s) require careful handling.")
    }
    if ([int]$summary.GpoCount -gt 0 -or [int]$summary.OuCount -gt 0) {
        $complexityLines.Add("Policy and structure: $([int]$summary.GpoCount) GPOs and $([int]$summary.OuCount) OUs shape migration targeting and validation.")
    }
    if ($duplicateConflictCount -gt 0 -or [int]$summary.UsersNonRoutableUPNCount -gt 0 -or [int]$summary.UsersSIDHistoryCount -gt 0) {
        $complexityLines.Add("Identity normalization: duplicates, UPN normalization, and SID history should be resolved before broader waves.")
    }
    if ([int]$summary.AdcsEnterpriseCaCount -gt 0) {
        $complexityLines.Add("PKI dependency: $([int]$summary.AdcsEnterpriseCaCount) enterprise CA instance(s) may add certificate and authentication requirements.")
    }
    if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['AdditionalComplexityDrivers'] -and $executiveSummaryConfig.AdditionalComplexityDrivers) {
        foreach ($driver in @($executiveSummaryConfig.AdditionalComplexityDrivers)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$driver)) { $complexityLines.Add([string]$driver) }
        }
    }

    $readinessNote = if ($executiveSummaryConfig -and $executiveSummaryConfig.PSObject.Properties['ReadinessOverride'] -and
        $executiveSummaryConfig.ReadinessOverride -and
        $executiveSummaryConfig.ReadinessOverride.PSObject.Properties['Note'] -and
        -not [string]::IsNullOrWhiteSpace([string]$executiveSummaryConfig.ReadinessOverride.Note)) {
        [string]$executiveSummaryConfig.ReadinessOverride.Note
    }
    elseif ($readinessCssClass -eq 'green') {
        'Current findings suggest a relatively manageable migration posture, with focused remediation and validation still recommended.'
    }
    elseif ($readinessCssClass -eq 'amber') {
        'The environment is workable for migration, but several issues should be addressed or explicitly accepted before cutover planning is finalized.'
    }
    else {
        'The environment has material blockers or elevated risk indicators that should be remediated or carefully sequenced before migration execution.'
    }

    $planningPriorityPhrases = New-Object System.Collections.Generic.List[string]
    if ($duplicateConflictCount -gt 0) {
        $planningPriorityPhrases.Add("identity conflicts with the target environment should be resolved early")
    }
    if ([int]$summary.ServiceAccountCandidatesCount -gt 0) {
        $planningPriorityPhrases.Add("service-account and application dependencies should be validated with stakeholders")
    }
    if ([int]$summary.UsersNonRoutableUPNCount -gt 0) {
        $planningPriorityPhrases.Add("namespace normalization should be completed before broader migration waves")
    }
    if ([int]$summary.WeakPasswordPoliciesCount -gt 0 -or [int]$summary.ObjectsRC4OnlyCount -gt 0) {
        $planningPriorityPhrases.Add("authentication and policy hardening should be addressed as part of readiness planning")
    }
    if ([int]$summary.PrivilegedAccountsCount -gt 0 -or [int]$summary.AdminSdHolderImpactCount -gt 0) {
        $planningPriorityPhrases.Add("privileged identities should move through dedicated validation and cutover steps")
    }
    if ([int]$summary.TrustCount -gt 0) {
        $planningPriorityPhrases.Add("trust relationships should be reviewed for sequencing and dependency impact")
    }
    if ([int]$summary.AdcsEnterpriseCaCount -gt 0) {
        $planningPriorityPhrases.Add("certificate-related dependencies should be included in migration design reviews")
    }

    $planningScopeSentence = "This assessment covers $([int]$summary.DomainsCount) domain(s), $([int]$summary.UsersTotal) users, $([int]$summary.GroupsTotal) groups, and $([int]$summary.ComputersTotal) devices in $($summary.ForestName)."
    $planningReadinessSentence = switch ($readinessCssClass) {
        'green' { 'Based on the current findings, the environment appears relatively manageable for migration planning with focused remediation and validation.'; break }
        'amber' { 'Based on the current findings, the environment appears workable for migration, but several items should be addressed or explicitly accepted before execution planning is finalized.'; break }
        default { 'Based on the current findings, the environment carries elevated migration risk and should move forward only with deliberate sequencing and targeted remediation.' }
    }
    $planningPrioritySentence = if ($planningPriorityPhrases.Count -gt 0) {
        'From a planning perspective, the highest priorities are to ensure that ' + (($planningPriorityPhrases | Select-Object -First 3) -join '; ') + '.'
    }
    else {
        'From a planning perspective, the main focus should be on validating business sequencing, application readiness, and target-state operating assumptions before cutover planning begins.'
    }
    $planningNarrative = "$planningScopeSentence $planningReadinessSentence $planningPrioritySentence"

    $sourceUpnSuffixValues = @()
    if ($forestSummaryRaw -and -not [string]::IsNullOrWhiteSpace([string]$forestSummaryRaw.UPNSuffixes)) {
        $sourceUpnSuffixValues = @(
            [string]$forestSummaryRaw.UPNSuffixes -split ';' |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.Trim().ToLowerInvariant() } |
                Sort-Object -Unique
        )
    }

    $targetUpnSuffixValues = @()
    if ($targetForestSummaryRaw -and -not [string]::IsNullOrWhiteSpace([string]$targetForestSummaryRaw.UPNSuffixes)) {
        $targetUpnSuffixValues = @(
            [string]$targetForestSummaryRaw.UPNSuffixes -split ';' |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_.Trim().ToLowerInvariant() } |
                Sort-Object -Unique
        )
    }

    $securityGroupsCount = @($allGroups | Where-Object { [string]$_.GroupCategory -match 'Security' }).Count
    $distributionGroupsCount = @($allGroups | Where-Object { [string]$_.GroupCategory -match 'Distribution' }).Count
    $mailEnabledGroupCount = @($allGroups | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Mail) }).Count
    $mailEnabledUserCount = @($allUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Mail) }).Count
    $mailEnabledContactCount = @($allContacts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Mail) }).Count
    $orphanedGpoCount = @(
        $allGpos |
            Where-Object {
                $gpoId = [string]$_.Id
                -not [string]::IsNullOrWhiteSpace($gpoId) -and
                -not @($allGpoLinks | Where-Object { [string]$_.GpoGuid -eq $gpoId }).Count
            }
    ).Count
    $gpoWithWmiFilterCount = @($allGpos | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.WmiFilter) }).Count
    $gpoDelegationCount = @($allGpoDelegation).Count
    $publishedSharedFolderCount = @($allPublishedSharedFolders).Count
    $publishedPrinterCount = @($allPublishedPrinters).Count
    $adminCountProtectedCount = @($allAdminCountObjects | Where-Object { Test-AdAnalysisBoolean $_.IsProtectedByAdminSDHolder }).Count

    $duplicateConflictTypeSummary = @(
        $duplicateConflicts |
            Group-Object ConflictType |
            Sort-Object Count -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    ConflictType = $_.Name
                    Count        = $_.Count
                }
            }
    )

    $topSpnServiceTypes = @(
        $allSpns |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.SPN) } |
            ForEach-Object {
                $spn = [string]$_.SPN
                $serviceType = ($spn -split '/')[0]
                if (-not [string]::IsNullOrWhiteSpace($serviceType)) {
                    [pscustomobject]@{
                        ServiceType = $serviceType
                        DomainFqdn  = [string]$_.DomainFqdn
                    }
                }
            } |
            Group-Object ServiceType |
            Sort-Object Count -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    ServiceType = $_.Name
                    Count       = $_.Count
                }
            }
    )

    $upnOverlapValues = @(
        $sourceUpnSuffixValues |
            Where-Object { $targetUpnSuffixValues -contains $_ } |
            Sort-Object -Unique
    )

    $smtpOverlapValues = @(
        $sourceMailDomains |
            Where-Object { $targetMailDomains -contains $_ } |
            Sort-Object -Unique
    )

    $forestModeText = if ($forestSummaryRaw) { [string]$forestSummaryRaw.ForestMode } else { 'Not collected' }
    $schemaMasterText = if ($forestSummaryRaw) { [string]$forestSummaryRaw.SchemaMaster } else { 'Unknown' }
    $domainNamingMasterText = if ($forestSummaryRaw) { [string]$forestSummaryRaw.DomainNamingMaster } else { 'Unknown' }
    $sourceUpnSuffixText = if ($sourceUpnSuffixValues.Count -gt 0) { $sourceUpnSuffixValues -join ', ' } else { 'None exported in this run' }
    $sourceMailDomainsText = if ($sourceMailDomains.Count -gt 0) { $sourceMailDomains -join ', ' } else { 'None discovered from mail-enabled users, groups, or contacts' }
    $upnOverlapText = if ($upnOverlapValues.Count -gt 0) { $upnOverlapValues -join ', ' } else { 'No overlap identified from exported suffix lists' }
    $smtpOverlapText = if ($smtpOverlapValues.Count -gt 0) { $smtpOverlapValues -join ', ' } else { 'No overlap identified from exported mail domains' }

    $topologyMetricsHtml = @(
        "<li><strong>Forest functional level:</strong> $(ConvertTo-HtmlText $forestModeText)</li>",
        "<li><strong>Root domain:</strong> $(ConvertTo-HtmlText $summary.ForestRootDomain)</li>",
        "<li><strong>Domains discovered:</strong> $([int]$summary.DomainsCount)</li>",
        "<li><strong>Trust relationships:</strong> $([int]$summary.TrustCount)</li>",
        "<li><strong>Sites / site links:</strong> $([int]$summary.SiteCount) site(s), $([int]$summary.SiteLinkCount) site link(s)</li>",
        "<li><strong>Forest-wide UPN suffixes:</strong> $([int]$summary.UpnSuffixCount)</li>",
        "<li><strong>Forest FSMO roles:</strong> Schema master $(ConvertTo-HtmlText $schemaMasterText), domain naming master $(ConvertTo-HtmlText $domainNamingMasterText)</li>"
    ) -join "`n"

    $domainTopologyRowsHtml = foreach ($domainRow in @($allDomainSummaryRows | Sort-Object DomainFqdn)) {
        "<tr><td>$(ConvertTo-HtmlText $domainRow.DomainFqdn)</td><td>$(ConvertTo-HtmlText $domainRow.NetBIOSName)</td><td>$(ConvertTo-HtmlText $domainRow.DomainMode)</td><td>$(ConvertTo-HtmlText $domainRow.PdcEmulator)</td><td>$(ConvertTo-HtmlText $domainRow.RidMaster)</td><td>$(ConvertTo-HtmlText $domainRow.InfrastructureMaster)</td></tr>"
    }

    $trustTableHtml = if ($trustRows.Count -gt 0) {
        $rows = foreach ($trust in $trustRows) {
            "<tr><td>$(ConvertTo-HtmlText $trust.Source)</td><td>$(ConvertTo-HtmlText $trust.Target)</td><td>$(ConvertTo-HtmlText $trust.Direction)</td><td>$(ConvertTo-HtmlText $trust.TrustType)</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $trust.SelectiveAuthentication))</td><td>$(ConvertTo-HtmlText $trust.SIDFilteringStatus)</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $trust.UsesAESKeys))</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $trust.UsesRC4Encryption))</td></tr>"
        }
        @"
            <table>
                <thead>
                    <tr>
                        <th>Source</th>
                        <th>Target</th>
                        <th>Direction</th>
                        <th>Type</th>
                        <th>Selective Auth</th>
                        <th>SID Filtering</th>
                        <th>Uses AES</th>
                        <th>Uses RC4</th>
                    </tr>
                </thead>
                <tbody>
                    $($rows -join "`n")
                </tbody>
            </table>
"@
    } else {
        "<p>No trust relationship data was exported for this run.</p>"
    }

    $siteTableHtml = if ($siteRows.Count -gt 0 -or $siteLinkRows.Count -gt 0) {
        $siteRowsHtml = foreach ($site in $siteRows) {
            "<tr><td>Site</td><td>$(ConvertTo-HtmlText $site.Name)</td><td>$(ConvertTo-HtmlText $site.Description)</td><td></td></tr>"
        }
        $siteLinkRowsHtml = foreach ($siteLink in $siteLinkRows) {
            "<tr><td>Site Link</td><td>$(ConvertTo-HtmlText $siteLink.Name)</td><td>$(ConvertTo-HtmlText $siteLink.SitesIncluded)</td><td>Cost $(ConvertTo-HtmlText $siteLink.Cost), every $(ConvertTo-HtmlText $siteLink.ReplicationFrequencyInMinutes) minutes</td></tr>"
        }
        @"
            <table>
                <thead>
                    <tr>
                        <th>Type</th>
                        <th>Name</th>
                        <th>Scope</th>
                        <th>Notes</th>
                    </tr>
                </thead>
                <tbody>
                    $(($siteRowsHtml + $siteLinkRowsHtml) -join "`n")
                </tbody>
            </table>
"@
    } else {
        "<p>No site or site-link data was exported for this run.</p>"
    }

    $identityRowsHtml = foreach ($ds in $domainSummaries) {
        $domain = [string]$ds.Domain
        $groupsInDomain = @($allGroups | Where-Object { [string]$_.DomainFqdn -eq $domain })
        $securityGroupsInDomain = @($groupsInDomain | Where-Object { [string]$_.GroupCategory -match 'Security' }).Count
        $distributionGroupsInDomain = @($groupsInDomain | Where-Object { [string]$_.GroupCategory -match 'Distribution' }).Count
        $s = $ds.Summary
        "<tr><td>$(ConvertTo-HtmlText $domain)</td><td>$([int]$s.UsersTotal)</td><td>$([int]$s.DisabledUsersCount)</td><td>$([int]$s.UsersStaleCount)</td><td>$([int]$s.GroupsTotal)</td><td>$securityGroupsInDomain</td><td>$distributionGroupsInDomain</td><td>$([int]$s.ComputersTotal)</td><td>$([int]$s.WorkstationsTotal)</td><td>$([int]$s.ServersTotal)</td><td>$([int]$s.ServiceAccountCandidatesCount)</td></tr>"
    }

    $dcRowsHtml = foreach ($dc in @($allDomainControllers | Sort-Object DomainFqdn, Site, HostName)) {
        "<tr><td>$(ConvertTo-HtmlText $dc.DomainFqdn)</td><td>$(ConvertTo-HtmlText $dc.HostName)</td><td>$(ConvertTo-HtmlText $dc.Site)</td><td>$(ConvertTo-HtmlText $dc.OperatingSystem)</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $dc.IsGlobalCatalog))</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $dc.IsPdc))</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $dc.IsReadOnly))</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $dc.IsEnabled))</td></tr>"
    }

    $passwordPolicyRowsHtml = foreach ($policy in @($allDefaultPasswordPolicies | Sort-Object DomainFqdn)) {
        "<tr><td>$(ConvertTo-HtmlText $policy.DomainFqdn)</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $policy.ComplexityEnabled))</td><td>$(ConvertTo-HtmlText $policy.MinPasswordLength)</td><td>$(ConvertTo-HtmlText $policy.PasswordHistoryCount)</td><td>$(ConvertTo-HtmlText $policy.MaxPasswordAgeDays)</td><td>$(ConvertTo-HtmlText $policy.LockoutThreshold)</td><td>$(ConvertTo-HtmlText (ConvertTo-AdDisplayBool $policy.ReversibleEncryptionEnabled))</td></tr>"
    }

    $namespaceRiskSummaryHtml = @(
        "<li><strong>UPN suffixes discovered:</strong> $(ConvertTo-HtmlText $sourceUpnSuffixText)</li>",
        "<li><strong>Non-routable UPN users:</strong> $([int]$summary.UsersNonRoutableUPNCount) account(s)</li>",
        "<li><strong>SMTP domains discovered:</strong> $(ConvertTo-HtmlText $sourceMailDomainsText)</li>"
    )

    if ($targetSummary) {
        $namespaceRiskSummaryHtml += "<li><strong>Overlapping UPN suffixes with target:</strong> $(ConvertTo-HtmlText $upnOverlapText)</li>"
        $namespaceRiskSummaryHtml += "<li><strong>Overlapping SMTP domains with target:</strong> $(ConvertTo-HtmlText $smtpOverlapText)</li>"
        $conflictSummaryText = if ($duplicateConflictTypeSummary.Count -gt 0) {
            ': ' + (($duplicateConflictTypeSummary | ForEach-Object { '{0} ({1})' -f $_.ConflictType, $_.Count }) -join ', ')
        }
        else {
            ''
        }
        $namespaceRiskSummaryHtml += "<li><strong>Identity conflicts with target:</strong> $duplicateConflictCount conflict(s)$conflictSummaryText</li>"
    }

    $namespaceRiskSummaryHtml = $namespaceRiskSummaryHtml -join "`n"

    $gpoRowsHtml = foreach ($gpo in @($allGpos | Sort-Object DomainFqdn, DisplayName)) {
        $linkCount = @($allGpoLinks | Where-Object { [string]$_.GpoGuid -eq [string]$gpo.Id }).Count
        $isUnlinked = if ($linkCount -gt 0) { 'No' } else { 'Yes' }
        "<tr><td>$(ConvertTo-HtmlText $gpo.DomainFqdn)</td><td>$(ConvertTo-HtmlText $gpo.DisplayName)</td><td>$(ConvertTo-HtmlText $gpo.GpoStatus)</td><td>$(ConvertTo-HtmlText $gpo.WmiFilter)</td><td>$linkCount</td><td>$isUnlinked</td></tr>"
    }

    $dependencySummaryHtml = @(
        "<li><strong>Service account candidates:</strong> $([int]$summary.ServiceAccountCandidatesCount)</li>",
        "<li><strong>SPNs discovered:</strong> $([int]$summary.SpnCount)</li>",
        "<li><strong>Enterprise CAs discovered:</strong> $([int]$summary.AdcsEnterpriseCaCount)</li>",
        "<li><strong>Published shared folders:</strong> $publishedSharedFolderCount</li>",
        "<li><strong>Published printers:</strong> $publishedPrinterCount</li>"
    ) -join "`n"

    $spnServiceTypeRowsHtml = foreach ($spnType in $topSpnServiceTypes) {
        "<tr><td>$(ConvertTo-HtmlText $spnType.ServiceType)</td><td>$([int]$spnType.Count)</td></tr>"
    }

    $domainTopologyTableBody = if ($domainTopologyRowsHtml) { $domainTopologyRowsHtml -join "`n" } else { "<tr><td colspan='6'>No domain summary rows were exported for this run.</td></tr>" }
    $dcTableBody = if ($dcRowsHtml) { $dcRowsHtml -join "`n" } else { "<tr><td colspan='8'>No domain controller inventory was exported for this run.</td></tr>" }
    $identityTableBody = if ($identityRowsHtml) { $identityRowsHtml -join "`n" } else { "<tr><td colspan='11'>No per-domain identity summary rows were exported for this run.</td></tr>" }
    $passwordPolicyTableBody = if ($passwordPolicyRowsHtml) { $passwordPolicyRowsHtml -join "`n" } else { "<tr><td colspan='7'>No default password policy rows were exported for this run.</td></tr>" }
    $gpoTableBody = if ($gpoRowsHtml) { $gpoRowsHtml -join "`n" } else { "<tr><td colspan='6'>No GPO inventory rows were exported for this run.</td></tr>" }
    $spnServiceTypeTableBody = if ($spnServiceTypeRowsHtml) { $spnServiceTypeRowsHtml -join "`n" } else { "<tr><td colspan='2'>No SPN data was exported for this run.</td></tr>" }

    $scopeHtml = (($scopeLines | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join "`n")
    $riskHtml = (($riskLines | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join "`n")
    $approachHtml = (($approachLines | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join "`n")
    $complexityHtml = (($complexityLines | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join "`n")

    # Build HTML
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AD Assessment Report - $($summary.ForestName)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 20px;
            margin-bottom: 30px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        header h1 { font-size: 28px; margin-bottom: 5px; }
        header p { font-size: 14px; opacity: 0.9; }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }
        .metric-card h3 { color: #667eea; font-size: 12px; text-transform: uppercase; margin-bottom: 10px; }
        .metric-card .value { font-size: 32px; font-weight: bold; color: #333; }
        .metric-card .label { font-size: 12px; color: #666; margin-top: 5px; }

        .health-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }
        .health-score {
            font-size: 48px;
            font-weight: bold;
            color: #667eea;
            margin: 10px 0;
        }
        .health-status {
            font-size: 18px;
            font-weight: bold;
            padding: 10px;
            border-radius: 4px;
            display: inline-block;
            margin-top: 10px;
        }
        .health-status.green { background: #d4edda; color: #155724; }
        .health-status.amber { background: #fff3cd; color: #856404; }
        .health-status.red { background: #f8d7da; color: #721c24; }

        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 18px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .summary-card h3 {
            color: #667eea;
            font-size: 16px;
            margin-bottom: 12px;
        }
        .summary-card ul {
            margin: 0;
            padding-left: 18px;
        }
        .summary-card li {
            margin: 8px 0;
        }
        .planning-brief {
            background: #f8fbff;
            border: 1px solid #d9e7f7;
            border-left: 5px solid #2d5aa7;
            border-radius: 8px;
            padding: 18px 20px;
            margin-bottom: 30px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }
        .planning-brief h2 {
            color: #2d5aa7;
            font-size: 18px;
            margin-bottom: 10px;
        }
        .planning-brief p {
            margin: 0;
            color: #334e68;
        }
        .readiness-score {
            font-size: 42px;
            font-weight: 700;
            color: #333;
            margin: 8px 0;
        }
        .summary-note {
            font-size: 13px;
            color: #666;
            margin-top: 10px;
        }

        .risk-overview {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        .risk-bars {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 15px;
            margin-top: 20px;
        }
        .risk-bar {
            padding: 15px;
            border-radius: 4px;
            text-align: center;
            color: white;
            font-weight: bold;
        }
        .risk-bar.critical { background: #dc3545; }
        .risk-bar.high { background: #fd7e14; }
        .risk-bar.medium { background: #ffc107; color: #333; }
        .risk-bar.low { background: #28a745; }
        .risk-bar .count { font-size: 24px; display: block; margin-bottom: 5px; }

        .section {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .section h2 {
            color: #667eea;
            font-size: 18px;
            margin-bottom: 15px;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        table th {
            background: #f8f9fa;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #667eea;
            font-size: 12px;
            color: #667eea;
        }
        table td {
            padding: 12px;
            border-bottom: 1px solid #e9ecef;
        }
        table tr:hover { background: #f8f9fa; }

        .finding {
            padding: 12px;
            margin: 10px 0;
            border-left: 4px solid #667eea;
            background: #f0f4ff;
        }
        .finding.critical { border-left-color: #dc3545; background: #fff5f5; }
        .finding.high { border-left-color: #fd7e14; background: #fff8f0; }
        .finding.medium { border-left-color: #ffc107; background: #fffbf0; }
        .finding-title {
            color: #1f3c88;
            text-decoration: none;
        }
        .finding-title:hover { text-decoration: underline; }
        .finding-links {
            margin-top: 6px;
            font-size: 12px;
        }
        .finding-links a {
            color: #1f3c88;
            text-decoration: none;
            margin-right: 12px;
        }
        .finding-links a:hover { text-decoration: underline; }

        .evidence-card {
            border: 1px solid #e9ecef;
            border-radius: 6px;
            padding: 16px;
            margin: 14px 0;
            background: #fbfcfe;
        }
        .evidence-card h3 {
            color: #2d5aa7;
            font-size: 16px;
            margin-bottom: 8px;
        }
        .evidence-meta {
            font-size: 13px;
            color: #555;
            margin-bottom: 8px;
        }
        .evidence-download {
            margin-top: 10px;
        }
        .evidence-download a {
            color: #1f3c88;
            text-decoration: none;
            font-weight: 600;
        }
        .evidence-download a:hover { text-decoration: underline; }

        .recommendation {
            padding: 12px;
            margin: 10px 0;
            background: #e8f4f8;
            border-left: 4px solid #17a2b8;
            border-radius: 4px;
        }

        footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 12px;
            margin-top: 40px;
            border-top: 1px solid #e9ecef;
        }

        .footer-text { opacity: 0.7; }
        .report-meta {
            background: #f8f9fa;
            padding: 10px;
            border-radius: 4px;
            font-size: 12px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Active Directory Assessment Report</h1>
            <p>Forest: $($summary.ForestName) | Root Domain: $($summary.ForestRootDomain) | Generated: $(Get-Date -Format 'MMMM d, yyyy h:mm tt')</p>
        </header>

        <div class="report-meta">
            <strong>Report Metadata:</strong>
            Domains Assessed: $($summary.DomainsCount) |
            Report ID: $(New-Guid) |
            Scope: Forest-wide automated assessment
        </div>

        <!-- Executive Summary -->
        <div class="section">
            <h2>Executive Summary</h2>
            <div class="summary-grid">
                <div class="summary-card">
                    <h3>Migration Scope</h3>
                    <ul>
                        $scopeHtml
                    </ul>
                </div>
                <div class="summary-card">
                    <h3>Key Risks</h3>
                    <ul>
                        $riskHtml
                    </ul>
                </div>
                <div class="summary-card">
                    <h3>Readiness</h3>
                    <div class="readiness-score">$readinessScore%</div>
                    <div class="health-status $readinessCssClass">$readinessStatus</div>
                    <div class="summary-note">$readinessNote</div>
                </div>
                <div class="summary-card">
                    <h3>Recommended Migration Approach</h3>
                    <ul>
                        $approachHtml
                    </ul>
                </div>
                <div class="summary-card">
                    <h3>Estimated Complexity Drivers</h3>
                    <ul>
                        $complexityHtml
                    </ul>
                </div>
            </div>
        </div>

        <div class="planning-brief">
            <h2>What This Means for Migration Planning</h2>
            <p>$(ConvertTo-HtmlText $planningNarrative)</p>
        </div>

        <!-- Key Metrics -->
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>Identity Objects</h3>
                <div class="value">$([int]$summary.UsersTotal)</div>
                <div class="label">Total Users</div>
            </div>
            <div class="metric-card">
                <h3>Groups</h3>
                <div class="value">$([int]$summary.GroupsTotal)</div>
                <div class="label">Total Groups</div>
            </div>
            <div class="metric-card">
                <h3>Computers</h3>
                <div class="value">$([int]$summary.ComputersTotal)</div>
                <div class="label">Total Computers</div>
            </div>
            <div class="metric-card">
                <h3>Privileged Accounts</h3>
                <div class="value">$([int]$summary.PrivilegedAccountsCount)</div>
                <div class="label">High-risk identities</div>
            </div>
        </div>

        <!-- Risk Overview -->
        <div class="risk-overview">
            <h2>Risk Overview</h2>
            <div class="risk-bars">
                <div class="risk-bar critical">
                    <span class="count">$($riskCounts.Critical)</span>
                    Critical
                </div>
                <div class="risk-bar high">
                    <span class="count">$($riskCounts.High)</span>
                    High
                </div>
                <div class="risk-bar medium">
                    <span class="count">$($riskCounts.Medium)</span>
                    Medium
                </div>
                <div class="risk-bar low">
                    <span class="count">$($riskCounts.Low)</span>
                    Low
                </div>
            </div>
        </div>

        <!-- Key Findings -->
        <div class="section">
            <h2>Key Findings</h2>
"@

    # Add findings based on metrics
    $findings = @()

    if ([int]$summary.UsersStaleCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = if ([double]$summary.UsersStalePct -gt 10) { 'high' } else { 'medium' }
            Title       = "Stale User Accounts"
            Description = "$([int]$summary.UsersStaleCount) users ($([double]$summary.UsersStalePct)%) have not logged in for 180+ days"
            Action      = "Review and disable inactive accounts per organizational policies"
            EvidenceKey = 'stale-users'
        }
    }

    if ([int]$summary.ComputersStaleCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = if ([double]$summary.ComputersStalePct -gt 10) { 'high' } else { 'medium' }
            Title       = "Stale Computer Accounts"
            Description = "$([int]$summary.ComputersStaleCount) computers ($([double]$summary.ComputersStalePct)%) have not logged in for 90+ days"
            Action      = "Clean up orphaned computer objects and outdated workstation accounts"
            EvidenceKey = 'stale-computers'
        }
    }

    if ([int]$summary.ObjectsRC4OnlyCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = 'high'
            Title       = "RC4-Only Encryption"
            Description = "$([int]$summary.ObjectsRC4OnlyCount) objects ($([double]$summary.ObjectsRC4OnlyPct)%) support RC4 encryption only"
            Action      = "Update encryption types to AES128-CTS-HMAC-SHA1-96 or stronger"
            EvidenceKey = 'weak-kerberos'
        }
    }

    if ([int]$summary.WeakPasswordPoliciesCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = 'high'
            Title       = "Weak Password Policies"
            Description = "$([int]$summary.WeakPasswordPoliciesCount) policies detected with insufficient complexity or expiration requirements"
            Action      = "Implement stronger password policies (14+ character, 60-90 day expiration)"
            EvidenceKey = 'weak-password-policy'
        }
    }

    if ([int]$summary.UsersSIDHistoryCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = 'medium'
            Title       = "SID History Present"
            Description = "$([int]$summary.UsersSIDHistoryCount) users ($([double]$summary.UsersSIDHistoryPct)%) have SID history attributes"
            Action      = "Review for migration artifacts; clean up after migration windows close"
            EvidenceKey = 'sid-history'
        }
    }

    if ([int]$summary.AdminSdHolderImpactCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = 'high'
            Title       = "AdminSDHolder Protected Accounts"
            Description = "$([int]$summary.AdminSdHolderImpactCount) accounts have adminCount=1 and are protected by AdminSDHolder"
            Action      = "Regularly audit privileged account permissions; remove unnecessary protections"
            EvidenceKey = 'adminsdholder'
        }
    }

    if ([int]$summary.ServiceAccountCandidatesCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = 'high'
            Title       = "Service Account Coordination Required"
            Description = "$([int]$summary.ServiceAccountCandidatesCount) service account candidates were identified and should be validated with application owners before migration waves begin"
            Action      = "Confirm ownership, authentication method, password handling, and application dependency for each service account"
            EvidenceKey = 'service-account-candidates'
        }
    }

    if ([int]$summary.PrivilegedAccountsCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = 'high'
            Title       = "Privileged Account Review Required"
            Description = "$([int]$summary.PrivilegedAccountsCount) privileged accounts are in scope and should be reviewed for cutover sequencing and post-migration access validation"
            Action      = "Validate privileged memberships, delegated access, and administrative access expectations before migrating sensitive accounts"
            EvidenceKey = 'privileged-accounts'
        }
    }

    if ([int]$summary.TrustCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = if ([int]$summary.TrustCount -gt 1) { 'high' } else { 'medium' }
            Title       = "Trust Relationships Need Migration Validation"
            Description = "$([int]$summary.TrustCount) trust relationship(s) were discovered and may affect dependency analysis, authentication flow, and cutover sequencing"
            Action      = "Review trust usage, name resolution, and dependency impact before finalizing migration sequencing"
            EvidenceKey = $null
        }
    }

    if ([int]$summary.AdcsEnterpriseCaCount -gt 0) {
        $findings += [pscustomobject]@{
            Level       = 'medium'
            Title       = "Certificate Services Dependencies Present"
            Description = "$([int]$summary.AdcsEnterpriseCaCount) AD CS enterprise CA instance(s) were detected and may influence certificate, authentication, and service migration planning"
            Action      = "Confirm certificate dependencies, enrollment workflows, and any target-state PKI requirements before migration"
            EvidenceKey = $null
        }
    }

    # Add findings from risk summary data (Flag, Count columns)
    if (@($riskSummary).Count -gt 0) {
        $staleCount = ($riskSummary | Where-Object { $_.Flag -eq 'StaleLastLogonOver180d' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($staleCount -gt 0) {
            $findings += [pscustomobject]@{
                Level       = 'high'
                Title       = "Accounts with Stale Logon Activity"
                Description = "$staleCount accounts have not logged on in 180+ days"
                Action      = "Audit and potentially disable inactive accounts"
                EvidenceKey = 'stale-users'
            }
        }

        $pwAgeCount = ($riskSummary | Where-Object { $_.Flag -eq 'PasswordAgeOver365d' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($pwAgeCount -gt 0) {
            $findings += [pscustomobject]@{
                Level       = 'high'
                Title       = "Accounts with Expired Password Age"
                Description = "$pwAgeCount accounts have not changed password in 365+ days"
                Action      = "Force password reset for affected accounts"
                EvidenceKey = 'expired-password-age'
            }
        }

        $aesCount = ($riskSummary | Where-Object { $_.Flag -eq 'Kerberos_NoAES' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($aesCount -gt 0) {
            $findings += [pscustomobject]@{
                Level       = 'high'
                Title       = "Weak Kerberos Encryption"
                Description = "$aesCount accounts do not support AES encryption"
                Action      = "Update encryption types to AES128-CTS-HMAC-SHA1-96 minimum"
                EvidenceKey = 'weak-kerberos'
            }
        }

        $upnCount = ($riskSummary | Where-Object { $_.Flag -match 'UPN_NonRoutableSuffix|UPN_SuffixNotInForestList' } | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($upnCount -gt 0) {
            $findings += [pscustomobject]@{
                Level       = 'medium'
                Title       = "Non-Routable UPN Suffixes"
                Description = "$upnCount accounts use non-routable UPN suffixes"
                Action      = "Review and update UPN suffixes to match organizational domain names"
                EvidenceKey = 'non-routable-upn'
            }
        }

        $disabledCount = ($riskSummary | Where-Object { $_.Flag -eq 'Disabled' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($disabledCount -gt 0) {
            $findings += [pscustomobject]@{
                Level       = 'low'
                Title       = "Disabled Account Migration Flags"
                Description = "$disabledCount disabled accounts have other risk indicators"
                Action      = "Review for cleanup if objects are no longer needed"
                EvidenceKey = $null
            }
        }
    }

    $evidenceKeysInUse = @(
        $findings |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.EvidenceKey) } |
            Select-Object -ExpandProperty EvidenceKey -Unique
    )

    $exportedEvidence = New-Object System.Collections.Generic.List[object]

    foreach ($evidenceKey in $evidenceKeysInUse) {
        $evidence = $findingEvidence[$evidenceKey]
        if (-not $evidence -or $evidence.RowCount -le 0) { continue }

        if (-not (Test-Path -LiteralPath $evidenceRoot)) {
            New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
        }

        $csvFileName = "{0}.csv" -f (ConvertTo-AdFindingSlug $evidenceKey)
        $csvPath = Join-Path $evidenceRoot $csvFileName
        $evidence.Rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Force

        $evidence.CsvPath = $csvPath
        $evidence.RelativeCsvPath = "$evidenceFolderName/$csvFileName"
        $exportedEvidence.Add($evidence)
    }

    foreach ($finding in $findings) {
        $evidence = if ($finding.EvidenceKey) { $findingEvidence[$finding.EvidenceKey] } else { $null }
        $titleHtml = if ($evidence -and $evidence.RowCount -gt 0) {
            "<a class='finding-title' href='#$($evidence.Anchor)'>$($finding.Title)</a>"
        } else {
            $finding.Title
        }

        $html += "            <div class='finding $($finding.Level)'>"
        $html += "                <strong>$titleHtml</strong><br/>"
        $html += "                $($finding.Description)<br/>"
        $html += "                <em style='color: #666;'>Action: $($finding.Action)</em>"
        if ($evidence -and $evidence.RowCount -gt 0) {
            $html += "                <div class='finding-links'><a href='#$($evidence.Anchor)'>View evidence</a><a href='$($evidence.RelativeCsvPath)'>Download CSV ($($evidence.RowCount) rows)</a></div>"
        }
        $html += "            </div>"
    }

    $html += @"
        </div>

        <!-- Per-Domain Breakdown -->
        <div class="section">
            <h2>Per-Domain Breakdown</h2>
            <table>
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>Users</th>
                        <th>Groups</th>
                        <th>Computers</th>
                        <th>Stale Users %</th>
                        <th>Stale Computers %</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($ds in $domainSummaries) {
        $s = $ds.Summary
        $html += "                    <tr>"
        $html += "                        <td>$($ds.Domain)</td>"
        $html += "                        <td>$([int]$s.UsersTotal)</td>"
        $html += "                        <td>$([int]$s.GroupsTotal)</td>"
        $html += "                        <td>$([int]$s.ComputersTotal)</td>"
        $html += "                        <td>$([double]$s.UsersStalePct)%</td>"
        $html += "                        <td>$([double]$s.ComputersStalePct)%</td>"
        $html += "                    </tr>"
    }

    $html += @"
                </tbody>
            </table>
        </div>

        <!-- Source Environment Assessment -->
        <div class="section">
            <h2>Environment Topology</h2>
            <ul>
                $topologyMetricsHtml
            </ul>
            <table>
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>NetBIOS</th>
                        <th>Functional Level</th>
                        <th>PDC Emulator</th>
                        <th>RID Master</th>
                        <th>Infrastructure Master</th>
                    </tr>
                </thead>
                <tbody>
                    $domainTopologyTableBody
                </tbody>
            </table>
            <h3 style="margin-top:20px;">Trust Relationships</h3>
            $trustTableHtml
            <h3 style="margin-top:20px;">Sites and Connectivity</h3>
            $siteTableHtml
        </div>

        <div class="section">
            <h2>Domain Controller Overview</h2>
            <p><strong>Summary:</strong> $([int]$summary.DomainControllerCount) domain controller(s) were discovered across the assessed source environment. The current discovery provides operating system, site placement, global catalog placement, and PDC identification. Patch level, replication health, and time synchronization will still need separate validation if they are required for migration readiness sign-off.</p>
            <table>
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>Host Name</th>
                        <th>Site</th>
                        <th>Operating System</th>
                        <th>Global Catalog</th>
                        <th>PDC</th>
                        <th>RODC</th>
                        <th>Enabled</th>
                    </tr>
                </thead>
                <tbody>
                    $dcTableBody
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2>Identity and Device Overview</h2>
            <p><strong>Summary:</strong> $([int]$summary.UsersTotal) users, $([int]$summary.GroupsTotal) groups, and $([int]$summary.ComputersTotal) devices are currently in scope. Group inventory includes $securityGroupsCount security group(s) and $distributionGroupsCount distribution group(s), which helps frame how much identity and access coordination may be required during migration.</p>
            <table>
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>Users</th>
                        <th>Disabled Users</th>
                        <th>Stale Users</th>
                        <th>Groups</th>
                        <th>Security Groups</th>
                        <th>Distribution Groups</th>
                        <th>Computers</th>
                        <th>Workstations</th>
                        <th>Servers</th>
                        <th>Service Accounts</th>
                    </tr>
                </thead>
                <tbody>
                    $identityTableBody
                </tbody>
            </table>
            <p style="margin-top:12px;"><strong>Mail-enabled objects:</strong> $mailEnabledUserCount user(s), $mailEnabledGroupCount group(s), and $mailEnabledContactCount contact(s) carry SMTP-style addressing in the exported data.</p>
        </div>

        <div class="section">
            <h2>Authentication and Access Considerations</h2>
            <p><strong>Summary:</strong> The current discovery highlights password policy posture, privileged-account exposure, AdminCount / AdminSDHolder status, service-account candidates, Kerberos encryption posture, SID history, protected users, AS-REP roastable users, and unconstrained delegation. Direct NTLM dependency auditing is not part of the current output, so legacy authentication reliance should still be validated separately if it is a migration concern.</p>
            <ul>
                <li><strong>Weak default password policies:</strong> $([int]$summary.WeakPasswordPoliciesCount)</li>
                <li><strong>Fine-grained password policies:</strong> $([int]$summary.FGPPCount)</li>
                <li><strong>Privileged accounts:</strong> $([int]$summary.PrivilegedAccountsCount)</li>
                <li><strong>AdminCount=1 objects:</strong> $adminCountProtectedCount protected object(s) and $([int]$summary.AdminSdHolderImpactCount) AdminSDHolder impact row(s)</li>
                <li><strong>SID history present:</strong> $([int]$summary.UsersSIDHistoryCount) user(s)</li>
                <li><strong>RC4-only or no-AES objects:</strong> $([int]$summary.ObjectsRC4OnlyCount)</li>
                <li><strong>AS-REP roastable users:</strong> $([int]$summary.AsrepRoastableUsersCount)</li>
                <li><strong>Unconstrained delegation objects:</strong> $([int]$summary.UnconstrainedDelegationCount)</li>
            </ul>
            <table>
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>Complexity Enabled</th>
                        <th>Min Length</th>
                        <th>Password History</th>
                        <th>Max Age (Days)</th>
                        <th>Lockout Threshold</th>
                        <th>Reversible Encryption</th>
                    </tr>
                </thead>
                <tbody>
                    $passwordPolicyTableBody
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2>Namespace and Identity Alignment</h2>
            <ul>
                $namespaceRiskSummaryHtml
            </ul>
        </div>

        <div class="section">
            <h2>Policy and Configuration</h2>
            <p><strong>Summary:</strong> $([int]$summary.GpoCount) GPOs, $(@($allGpoLinks).Count) link rows, and $gpoDelegationCount delegation rows were exported. $gpoWithWmiFilterCount GPO(s) reference WMI filters and $orphanedGpoCount appear unlinked based on exported link data, which can be useful when identifying policies that may need cleanup or redesign before migration.</p>
            <table>
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>GPO</th>
                        <th>Status</th>
                        <th>WMI Filter</th>
                        <th>Link Count</th>
                        <th>Unlinked</th>
                    </tr>
                </thead>
                <tbody>
                    $gpoTableBody
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2>Application and Service Considerations</h2>
            <ul>
                $dependencySummaryHtml
            </ul>
            <table>
                <thead>
                    <tr>
                        <th>SPN Service Type</th>
                        <th>Count</th>
                    </tr>
                </thead>
                <tbody>
                    $spnServiceTypeTableBody
                </tbody>
            </table>
        </div>

        <!-- Evidence and Downloads -->
        <div class="section">
            <h2>Evidence and Downloads</h2>
"@

    if ($exportedEvidence.Count -gt 0) {
        foreach ($evidence in $exportedEvidence) {
            $html += "            <div class='evidence-card' id='$($evidence.Anchor)'>"
            $html += "                <h3>$($evidence.Title)</h3>"
            $html += "                <div class='evidence-meta'><strong>Objects exported:</strong> $($evidence.RowCount)</div>"
            $html += "                <div class='evidence-meta'><strong>Basis:</strong> $($evidence.SourceSummary)</div>"
            $html += "                <div class='evidence-meta'>$($evidence.EvidenceSummary)</div>"
            $html += "                <div class='evidence-download'><a href='$($evidence.RelativeCsvPath)'>Download supporting CSV</a></div>"
            $html += "            </div>"
        }
    } else {
        $html += "            <div class='evidence-card'>No downloadable evidence files were generated for this assessment.</div>"
    }

    $html += @"
        </div>

        <!-- Recommendations -->
        <div class="section">
            <h2>Remediation Roadmap</h2>
"@

    $recommendations = @(
        "1. <strong>Immediate (0-30 days):</strong> Disable stale user and computer accounts; address weak password policies",
        "2. <strong>Short-term (1-3 months):</strong> Update encryption settings to AES; audit and clean SID history",
        "3. <strong>Medium-term (3-6 months):</strong> Review AdminSDHolder protected accounts; implement stronger access controls",
        "4. <strong>Ongoing:</strong> Monitor for new stale accounts; enforce organizational security policies"
    )

    foreach ($rec in $recommendations) {
        $html += "            <div class='recommendation'>$rec</div>"
    }

    $html += @"
        </div>

        <footer>
            <p class="footer-text">This report was generated by Paul Lagana Toolkit v0.1.1</p>
            <p class="footer-text">For detailed findings, use the evidence download links included in this report</p>
        </footer>
    </div>
</body>
</html>
"@

    # Write HTML to file
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

    [pscustomobject]@{
        ReportPath    = $OutputPath
        ForestName    = $summary.ForestName
        HealthScore   = $healthScore
        HealthStatus  = $healthStatus
        ReadinessScore = $readinessScore
        ReadinessStatus = $readinessStatus
        TotalFindings = $findings.Count
        CriticalRisks = $riskCounts.Critical
        HighRisks     = $riskCounts.High
        EvidenceRoot  = if (Test-Path -LiteralPath $evidenceRoot) { $evidenceRoot } else { $null }
        EvidenceFiles = @($exportedEvidence | Select-Object -ExpandProperty CsvPath)
    }
}
