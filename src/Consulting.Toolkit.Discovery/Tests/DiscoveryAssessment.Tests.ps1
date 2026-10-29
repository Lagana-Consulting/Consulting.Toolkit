# Expected assessment results must survive native -> CSV -> imported inputs.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Consulting.Toolkit.Discovery.psd1') -Force -PassThru -WarningAction SilentlyContinue
$root = Join-Path ([IO.Path]::GetTempPath()) ('AdDiscoveryAssessment-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null

& $module {
    param($Root)
    function Assert-Assessment {
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }
    function Get-AdAdForest { param($ForestName); [pscustomobject]@{Name=$ForestName;RootDomain=$ForestName} }
    function Get-AdAdDomains { param($Forest); 'example.test' }
    function Get-ADReplicationSiteLink {
        [CmdletBinding()] param($Filter,$Server)
        foreach ($cost in @(100,500,501,1000,1001)) {
            [pscustomobject]@{Name="Link$cost";Cost=$cost;ReplicationFrequencyInMinutes=180;SitesIncluded=@('A','B');DistinguishedName="CN=Link$cost";Description=''}
        }
    }
    $defs = Get-AdSchemaDefinitions
    function New-Account {
        param($Schema,$Name,$Types,$Risk)
        $values = [ordered]@{}
        foreach ($column in $defs[$Schema]) { $values[$column.Column] = $null }
        $values.DomainFqdn = 'example.test'; $values.Name = $Name; $values.SamAccountName = $Name
        $values.DistinguishedName = "CN=$Name,DC=example,DC=test"
        $values.Enabled=$true; $values.LastLogonDays=0; $values.SPNCount=0
        $values.EncryptionTypes=$Types; $values.EncryptionRisk=$Risk
        if ($Schema -eq 'Users') {
            $values.UserPrincipalName="$Name@example.test"; $values.IsKnownUpnSuffix=$true
            $values.IsNonRoutableUpnSuffix=$false; $values.PasswordAgeDays=0; $values.SidHistoryCount=0
        } else { $values.IsServer=$false; $values.OperatingSystem='Windows 11' }
        [pscustomobject]$values
    }
    function Roundtrip {
        param([AllowEmptyCollection()][object[]]$Rows,$Name,[string]$Schema)
        $path = Join-Path $Root ($Name + '.csv')
        $Rows | Export-AdCsvSafe -Path $path -SchemaName $Schema -AllowEmpty -Force | Out-Null
        Import-Csv -LiteralPath $path
    }
    $users = @(
        New-Account Users 'rc4' 'RC4_HMAC' 'Medium'
        New-Account Users 'des' 'DES_CBC_CRC' 'High'
        New-Account Users 'des-aes' 'DES_CBC_CRC;AES256_HMAC_SHA1' 'High'
        New-Account Users 'fast' 'FAST_SUPPORTED' 'Unknown'
        New-Account Users 'unknown' '' 'Unknown'
        New-Account Users 'rc4-aes' 'RC4_HMAC;AES128_HMAC_SHA1' 'Low'
    )
    $users[0].Enabled=$false; $users[0].LastLogonDays=181; $users[0].PasswordAgeDays=366
    $users[0].SidHistoryCount=1; $users[0].IsNonRoutableUpnSuffix=$true
    $users[0].IsKnownUpnSuffix=$false; $users[0].SPNCount=1
    $users[1].LastLogonDays=180; $users[1].PasswordAgeDays=365
    $users[4].Enabled=$null; $users[4].IsKnownUpnSuffix=$null; $users[4].IsNonRoutableUpnSuffix=$null
    $users[4].LastLogonDays=$null; $users[4].PasswordAgeDays=$null
    $computers = @(
        New-Account Computers 'pc-rc4' 'RC4_HMAC' 'Medium'
        New-Account Computers 'server-aes' 'DES_CBC_MD5;AES256_HMAC_SHA1' 'High'
        New-Account Computers 'pc-des' 'DES_CBC_MD5' 'High'
        New-Account Computers 'pc-unknown' '' 'Unknown'
    )
    $computers[0].Enabled=$false; $computers[0].LastLogonDays=91; $computers[0].OperatingSystem='Windows 7'
    $computers[1].LastLogonDays=90; $computers[1].IsServer=$true; $computers[1].OperatingSystem='Windows Server 2012 R2'
    $computers[2].IsServer=$null; $computers[2].OperatingSystem='Windows 7'; $computers[2].LastLogonDays=$null
    $computers[3].Enabled=$null
    $sites = @(Get-AdSiteLinkCostAnalysis)
    $policies = @(2,3,10 | ForEach-Object { [pscustomobject]@{WeaknessCount=$_} })
    $nesting = @(4,5,10,-1 | ForEach-Object { [pscustomobject]@{NestingDepth=$_} })
    $ous = @(4,5,10 | ForEach-Object { [pscustomobject]@{Depth=$_} })
    $fsmo = @($true,$false,$null | ForEach-Object { [pscustomobject]@{IsAvailable=$_} })
    $summaryArgs = @{
        ForestName='example.test';AllUsers=$users;AllComputers=$computers;AllGroups=@();PrivilegedAccounts=@()
        SiteLinkData=$sites;WeakPasswordPoliciesData=$policies;GroupNestingData=$nesting;OuDepthData=$ous;FsmoAvailabilityData=$fsmo
    }
    $nativeSummary = Get-AdAssessmentSummary @summaryArgs
    $nativeFlags = @(Get-AdMigrationRiskFlags -AllUsers $users -AllComputers $computers)
    $expectedFlags = @{
        rc4='UPN_NonRoutableSuffix;UPN_SuffixNotInForestList;Disabled;PasswordAgeOver365d;StaleLastLogonOver180d;HasSPN(ServiceAcctCandidate);Kerberos_NoAES'
        des='Kerberos_NoAES'
        'pc-rc4'='Kerberos_NoAES;Disabled;StaleLastLogonOver90d;LegacyWorkstationOS'
        'server-aes'='LegacyServerOS'
        'pc-des'='Kerberos_NoAES'
    }
    foreach ($mode in @('Native','Csv')) {
        if ($mode -eq 'Csv') {
            $summaryArgs.AllUsers = @(Roundtrip $users Users Users)
            $summaryArgs.AllComputers = @(Roundtrip $computers Computers Computers)
            $summaryArgs.SiteLinkData = @(Roundtrip $sites Sites SiteLink_CostAnalysis)
            $summaryArgs.WeakPasswordPoliciesData = @(Roundtrip $policies Policies)
            $summaryArgs.GroupNestingData = @(Roundtrip $nesting Nesting)
            $summaryArgs.OuDepthData = @(Roundtrip $ous Ous)
            $summaryArgs.FsmoAvailabilityData = @(Roundtrip $fsmo Fsmo)
        }
        $summary = Get-AdAssessmentSummary @summaryArgs
        $expected = @{
            UsersTotal=6;ComputersTotal=4;ObjectsRC4OnlyCount=2;ObjectsRC4OnlyPct=20
            UsersStaleCount=1;UsersStalePct=16.67;ComputersStaleCount=1;ComputersStalePct=25
            UsersSIDHistoryCount=1;UsersSIDHistoryPct=16.67;UsersNonRoutableUPNCount=1;UsersNonRoutableUPNPct=16.67
            WeakPasswordPoliciesCount=2;HighDepthGroupsCount=2;HighDepthOUsCount=2;FsmoUnavailableCount=1;HighCostSiteLinksCount=3
        }
        foreach ($key in $expected.Keys) { Assert-Assessment ($summary.$key -eq $expected[$key]) "$mode $key expected $($expected[$key]), got $($summary.$key)" }
        foreach ($column in $defs.Assessment_Summary.Column | Where-Object { $_ -ne 'RunTimestamp' }) {
            Assert-Assessment ($summary.$column -eq $nativeSummary.$column) "$mode summary parity: $column"
        }
        $flags = @(Get-AdMigrationRiskFlags -AllUsers $summaryArgs.AllUsers -AllComputers $summaryArgs.AllComputers)
        Assert-Assessment ($flags.Count -eq $expectedFlags.Count) "$mode risk account count"
        foreach ($row in $flags) { Assert-Assessment ($expectedFlags.ContainsKey($row.SamAccountName) -and $row.Flags -eq $expectedFlags[$row.SamAccountName]) "$mode exact flags for $($row.SamAccountName)" }
        $flagSummary = @(Get-AdMigrationRiskFlagsSummary -RiskFlagsData $flags)
        Assert-Assessment (@($flagSummary | Where-Object { $_.Flag -eq 'Kerberos_NoAES' -and $_.Count -eq 2 }).Count -eq 2) "$mode NoAES counts for users and computers"
        Write-Host "PASS: $mode assessment counts, percentages, Boolean states, numeric thresholds, and exact migration flags"
    }
    $empty = Get-AdAssessmentSummary -ForestName example.test -AllUsers @() -AllComputers @() -AllGroups @() -PrivilegedAccounts @()
    Assert-Assessment ($empty.ObjectsRC4OnlyPct -eq 0 -and $empty.UsersStalePct -eq 0 -and $empty.ComputersStalePct -eq 0) 'Empty percentages are zero'
    $legacy = Get-AdAssessmentSummary -ForestName example.test -AllUsers @() -AllComputers @() -AllGroups @() -PrivilegedAccounts @() -SiteLinkData @([pscustomobject]@{Assessment='High Cost'},[pscustomobject]@{Assessment='Very High'})
    Assert-Assessment ($legacy.HighCostSiteLinksCount -eq 2) 'Historical site-link labels remain accepted'

    # Never round partial days up across the cleanup threshold; clamp future dates.
    $now = [datetime]::UtcNow
    $disabled = @(
        New-Account Users 'partial-day' '' Unknown
        New-Account Users 'old' '' Unknown
        New-Account Users 'missing-date' '' Unknown
        New-Account Users 'future' '' Unknown
    )
    foreach ($row in $disabled) { $row.Enabled=$false }
    $disabled[0].WhenChanged=$now.AddDays(-180.9)
    $disabled[1].WhenChanged=[datetimeoffset]::new($now.AddDays(-182)).ToOffset([timespan]::FromHours(5.5))
    $disabled[2].WhenChanged=$null
    $disabled[3].WhenChanged=$now.AddDays(2)
    foreach ($culture in @('en-US','en-GB','fr-FR')) {
        $previousCulture = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($culture)
            $imported = @(Roundtrip $disabled ("Disabled-$culture") Users)
            $results = @(Get-AdDisabledAccounts -AllUsers $imported -AllComputers @())
            $partial = @($results | Where-Object SamAccountName -eq 'partial-day')[0]
            $old = @($results | Where-Object SamAccountName -eq 'old')[0]
            $missing = @($results | Where-Object SamAccountName -eq 'missing-date')[0]
            $future = @($results | Where-Object SamAccountName -eq 'future')[0]
            Assert-Assessment ($partial.DaysSinceChange -eq 180 -and $partial.CleanupCandidate -eq 'No') "$culture floors elapsed days"
            Assert-Assessment ($old.DaysSinceChange -eq 182 -and $old.CleanupCandidate -eq 'Yes') "$culture preserves UTC offsets"
            Assert-Assessment ($null -eq $missing.DaysSinceChange -and $missing.CleanupCandidate -eq 'Unknown') "$culture preserves missing dates"
            Assert-Assessment ($future.DaysSinceChange -eq 0) "$culture clamps future changes"
            $null = Roundtrip $results ("DisabledResults-$culture") DisabledAccounts
            $date = [datetime]::SpecifyKind([datetime]::new(2025,4,3,13,30,0),[DateTimeKind]::Utc)
            $raw = @(Roundtrip @([pscustomobject]@{Date=$date;Text='03/04/2025';Enabled=$false}) ("Date-$culture"))
            Assert-Assessment ($raw[0].Date -eq '2025-04-03T13:30:00.0000000Z' -and $raw[0].Text -eq '03/04/2025' -and $raw[0].Enabled -eq 'False') "$culture serializes native dates, preserving strings and Boolean values"
        } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $previousCulture }
        Write-Host "PASS: $culture date round trips, nullable change dates, cleanup thresholds, and offset handling"
    }
    # Bad supplied data must fail visibly, rather than turn into a clean result.
    foreach ($bad in @(
        @{Property='Enabled';Value='not-a-bool'},
        @{Property='LastLogonDays';Value='many'},
        @{Property='PasswordAgeDays';Value='2.5'}
    )) {
        $row = New-Account Users bad '' Unknown
        $row.($bad.Property) = $bad.Value
        $failed=$false
        try { Get-AdMigrationRiskFlags -AllUsers @($row) -AllComputers @() | Out-Null } catch { $failed = $_.Exception.Message -like ('*'+$bad.Property+'*') }
        Assert-Assessment $failed "Malformed $($bad.Property) names the offending field"
    }
    $badDate = New-Account Users 'bad-date' '' Unknown; $badDate.Enabled=$false; $badDate.WhenChanged='not-a-date'
    $failed=$false
    try { Get-AdDisabledAccounts -AllUsers @($badDate) -AllComputers @() | Out-Null } catch { $failed=$_.Exception.Message -like '*WhenChanged*' }
    Assert-Assessment $failed 'Malformed date is surfaced'
    $comma = [pscustomobject]@{RiskCategory='Account, Policy';RiskName='Name, with commas';RiskLevel='High'}
    $risk = @(Get-AdRiskSummary -RiskRows @($comma,$comma))
    Assert-Assessment ($risk.Count -eq 1 -and $risk[0].RiskName -eq $comma.RiskName -and $risk[0].RiskCategory -eq $comma.RiskCategory -and $risk[0].Count -eq 2) 'Risk grouping preserves commas'
    $summary = @(Get-AdMigrationRiskFlagsSummary -RiskFlagsData @([pscustomobject]@{Flags='Disabled;Disabled; ;';ObjectClass='user'},[pscustomobject]@{Flags='';ObjectClass='user'}))
    Assert-Assessment ($summary.Count -eq 1 -and $summary[0].Flag -eq 'Disabled' -and $summary[0].Count -eq 1) 'Flag counts exclude blank and repeated flags on an account'
    Write-Host "PASS: empty datasets, historical labels, malformed input failures, and accurate risk grouping; outputs: $Root"
} $root
