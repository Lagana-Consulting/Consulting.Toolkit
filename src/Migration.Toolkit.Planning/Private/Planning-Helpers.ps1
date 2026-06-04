function Import-AdPlanningCsvSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    try {
        return @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    }
    catch {
        Write-Warning "Failed to import CSV: $Path. $($_.Exception.Message)"
        return @()
    }
}

function Test-AdPlanningBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value) { return $false }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    return $text -in @('true', '1', 'yes', 'y')
}

function ConvertTo-AdPlanningInt {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [int]$Default = 0
    )

    if ($null -eq $Value) { return $Default }

    $parsed = 0
    if ([int]::TryParse(([string]$Value).Trim(), [ref]$parsed)) {
        return $parsed
    }

    return $Default
}

function Get-AdPlanningTimestamp {
    [CmdletBinding()]
    param()

    return Get-Date -Format 'yyyyMMdd-HHmmss'
}

function Get-AdPlanningPackageLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][int]$Index
    )

    $leaf = Split-Path -Path $RunRoot -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        $leaf = "Run$Index"
    }

    $safeLeaf = ($leaf -replace '[^\w\.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeLeaf)) {
        $safeLeaf = "Run$Index"
    }

    return ('source_{0:00}_{1}' -f $Index, $safeLeaf)
}

function Resolve-AdPlanningRules {
    [CmdletBinding()]
    param(
        [string]$PlanningConfigPath
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $defaultPath = Join-Path $moduleRoot 'config\PlanningRules.Standard.json'
    $path = if (-not [string]::IsNullOrWhiteSpace($PlanningConfigPath)) { $PlanningConfigPath } else { $defaultPath }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Planning config not found: $path"
    }

    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-AdPlanningMailDomains {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][array]$Records
    )

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

function Test-AdPlanningBuiltInGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Group,
        [Parameter(Mandatory)]$Rules
    )

    $dn = [string]$Group.DistinguishedName
    $sam = ([string]$Group.SamAccountName).Trim().ToLowerInvariant()

    foreach ($prefix in @($Rules.BuiltInGroupDnPrefixes)) {
        if (-not [string]::IsNullOrWhiteSpace($prefix) -and $dn.StartsWith([string]$prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $sam -in @($Rules.BuiltInGroupSamAccountNames | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
}

function Get-AdPlanningObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$PropertyName
    )

    if ($null -eq $InputObject -or -not $InputObject.PSObject.Properties[$PropertyName]) {
        return ''
    }

    return [string]$InputObject.PSObject.Properties[$PropertyName].Value
}

function New-AdPlanningGroupKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Group,
        [string]$SamAccountNameProperty = 'SamAccountName',
        [string]$DistinguishedNameProperty = 'DistinguishedName'
    )

    $domain = (Get-AdPlanningObjectPropertyValue -InputObject $Group -PropertyName 'DomainFqdn').Trim().ToLowerInvariant()
    $sam = (Get-AdPlanningObjectPropertyValue -InputObject $Group -PropertyName $SamAccountNameProperty).Trim().ToLowerInvariant()
    $dn = (Get-AdPlanningObjectPropertyValue -InputObject $Group -PropertyName $DistinguishedNameProperty).Trim().ToLowerInvariant()

    if (-not [string]::IsNullOrWhiteSpace($domain) -and -not [string]::IsNullOrWhiteSpace($sam)) {
        return ("{0}|sam|{1}" -f $domain, $sam)
    }

    if (-not [string]::IsNullOrWhiteSpace($domain) -and -not [string]::IsNullOrWhiteSpace($dn)) {
        return ("{0}|dn|{1}" -f $domain, $dn)
    }

    if (-not [string]::IsNullOrWhiteSpace($dn)) {
        return ("dn|{0}" -f $dn)
    }

    return ''
}

function Add-AdPlanningGroupReviewSignal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Signals,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace($Key)) { return }
    if (-not $Signals.ContainsKey($Key)) {
        $Signals[$Key] = New-Object System.Collections.Generic.List[string]
    }
    if (-not $Signals[$Key].Contains($Reason)) {
        [void]$Signals[$Key].Add($Reason)
    }
}

function Get-AdPlanningGroupReviewSignals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot
    )

    $signals = @{}
    $domainRoot = Join-Path $RunRoot '20_domains'
    if (-not (Test-Path -LiteralPath $domainRoot -PathType Container)) {
        return $signals
    }

    $signalFiles = @(
        [pscustomobject]@{ Filter = 'AD__Domain__Identity__GroupsEmpty__*.csv'; Reason = 'EmptyGroup' }
        [pscustomobject]@{ Filter = 'AD__Domain__Identity__GroupsSingleMember__*.csv'; Reason = 'SingleMemberGroup' }
        [pscustomobject]@{ Filter = 'AD__Domain__Identity__GroupsWithDisabledOrInactiveMembers__*.csv'; Reason = 'DisabledOrInactiveGroupMember' }
    )

    foreach ($signalFile in $signalFiles) {
        $files = @(
            Get-ChildItem -LiteralPath $domainRoot -Recurse -Filter $signalFile.Filter -File -ErrorAction SilentlyContinue |
                Sort-Object FullName
        )
        foreach ($file in $files) {
            foreach ($row in @(Import-AdPlanningCsvSafe -Path $file.FullName)) {
                $key = New-AdPlanningGroupKey -Group $row -SamAccountNameProperty 'GroupSamAccountName' -DistinguishedNameProperty 'GroupDistinguishedName'
                Add-AdPlanningGroupReviewSignal -Signals $signals -Key $key -Reason $signalFile.Reason
            }
        }
    }

    return $signals
}

function Get-AdPlanningRunData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot
    )

    if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
        throw "Run root not found: $RunRoot"
    }

    $forestSummary = @(
        Import-AdPlanningCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Summary__Forest.csv')
    ) | Select-Object -First 1

    $upnSuffixes = @(
        Import-AdPlanningCsvSafe -Path (Join-Path $RunRoot '10_forest\AD__Forest__Identity__UpnSuffixes__Forest.csv')
    )

    $trustFile = Get-ChildItem -LiteralPath (Join-Path $RunRoot '10_forest') -Filter 'AD__Forest__Trusts__*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $trusts = if ($null -ne $trustFile) { @(Import-AdPlanningCsvSafe -Path $trustFile.FullName) } else { @() }

    $users = New-Object System.Collections.Generic.List[object]
    $groups = New-Object System.Collections.Generic.List[object]
    $computers = New-Object System.Collections.Generic.List[object]
    $serviceAccounts = New-Object System.Collections.Generic.List[object]
    $privilegedAccounts = New-Object System.Collections.Generic.List[object]
    $passwordPolicies = New-Object System.Collections.Generic.List[object]

    $domainRoot = Join-Path $RunRoot '20_domains'
    $domainFolders = @(Get-ChildItem -LiteralPath $domainRoot -Directory -ErrorAction SilentlyContinue)
    foreach ($domainFolder in $domainFolders) {
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Identity__Users__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdPlanningCsvSafe -Path $_.FullName })) { [void]$users.Add($row) }
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Identity__Groups__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdPlanningCsvSafe -Path $_.FullName })) { [void]$groups.Add($row) }
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Identity__ComputersAll__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdPlanningCsvSafe -Path $_.FullName })) { [void]$computers.Add($row) }
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Identity__ServiceAccountCandidates__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdPlanningCsvSafe -Path $_.FullName })) { [void]$serviceAccounts.Add($row) }
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Security__PrivilegedAccounts__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdPlanningCsvSafe -Path $_.FullName })) { [void]$privilegedAccounts.Add($row) }
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Security__PasswordPolicyDefault__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdPlanningCsvSafe -Path $_.FullName })) { [void]$passwordPolicies.Add($row) }
    }

    $usersArray = $users.ToArray()
    $groupsArray = $groups.ToArray()
    $computersArray = $computers.ToArray()
    $serviceAccountsArray = $serviceAccounts.ToArray()
    $privilegedAccountsArray = $privilegedAccounts.ToArray()
    $passwordPoliciesArray = $passwordPolicies.ToArray()

    $domainFolderCount = @($domainFolders).Count
    $domainCount = if ($forestSummary -and $forestSummary.DomainCount) {
        ConvertTo-AdPlanningInt -Value $forestSummary.DomainCount -Default $domainFolderCount
    }
    else {
        $domainFolderCount
    }
    $usersTotal = @($usersArray).Count
    $groupsTotal = @($groupsArray).Count
    $computersTotal = @($computersArray).Count
    $serverCount = @($computersArray | Where-Object { Test-AdPlanningBoolean $_.IsServer }).Count
    $workstationCount = @($computersArray | Where-Object { -not (Test-AdPlanningBoolean $_.IsServer) }).Count
    $disabledUsersCount = @($usersArray | Where-Object { -not (Test-AdPlanningBoolean $_.Enabled) }).Count
    $serviceAccountCount = @($serviceAccountsArray).Count
    $privilegedAccountCount = @($privilegedAccountsArray).Count
    $nonRoutableUpnCount = @($usersArray | Where-Object { Test-AdPlanningBoolean $_.IsNonRoutableUpnSuffix }).Count
    $trustCount = @($trusts).Count
    $upnSuffixCount = @($upnSuffixes).Count

    $summary = [pscustomobject]@{
        ForestName             = if ($forestSummary) { [string]$forestSummary.ForestName } else { Split-Path -Path $RunRoot -Leaf }
        RootDomain             = if ($forestSummary) { [string]$forestSummary.RootDomain } else { '' }
        ForestMode             = if ($forestSummary) { [string]$forestSummary.ForestMode } else { '' }
        DomainCount            = $domainCount
        UsersTotal             = $usersTotal
        GroupsTotal            = $groupsTotal
        ComputersTotal         = $computersTotal
        ServerCount            = $serverCount
        WorkstationCount       = $workstationCount
        DisabledUsersCount     = $disabledUsersCount
        StaleUsersCount        = 0
        StaleComputersCount    = 0
        ServiceAccountCount    = $serviceAccountCount
        PrivilegedAccountCount = $privilegedAccountCount
        NonRoutableUpnCount    = $nonRoutableUpnCount
        TrustCount             = $trustCount
        UpnSuffixCount         = $upnSuffixCount
    }

    return [pscustomobject]@{
        RunRoot             = $RunRoot
        ForestSummary       = $forestSummary
        Summary             = $summary
        DomainFolders       = @($domainFolders)
        Users               = @($usersArray)
        Groups              = @($groupsArray)
        Computers           = @($computersArray)
        ServiceAccounts     = @($serviceAccountsArray)
        PrivilegedAccounts  = @($privilegedAccountsArray)
        PasswordPolicies    = @($passwordPoliciesArray)
        UpnSuffixes         = @($upnSuffixes)
        Trusts              = @($trusts)
        MailDomains         = @(Get-AdPlanningMailDomains -Records (@($usersArray) + @($groupsArray)))
    }
}

function Invoke-AdPlanningDuplicateCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$SourceRunRoot,
        [Parameter(Mandatory)][string]$TargetRunRoot,
        [Parameter(Mandatory)][string]$OutputRoot
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $srcRoot = Split-Path -Parent $moduleRoot
    $analysisManifest = Join-Path $srcRoot 'Migration.Toolkit.Analysis\Migration.Toolkit.Analysis.psd1'

    if (-not (Get-Command Invoke-AdCrossForestDuplicateCheck -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath $analysisManifest -PathType Leaf) {
            Import-Module $analysisManifest -Force
        }
    }

    if (-not (Get-Command Invoke-AdCrossForestDuplicateCheck -ErrorAction SilentlyContinue)) {
        Write-Warning "Invoke-AdCrossForestDuplicateCheck is not available. Duplicate checking will be skipped."
        return @()
    }

    return @(
        Invoke-AdCrossForestDuplicateCheck `
            -SourceRunRoots $SourceRunRoot `
            -TargetRunRoot $TargetRunRoot `
            -OutputRoot $OutputRoot `
            -PassThru
    )
}
