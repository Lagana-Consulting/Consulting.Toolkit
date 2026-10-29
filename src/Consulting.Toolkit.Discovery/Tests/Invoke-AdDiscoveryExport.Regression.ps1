# Run with powershell.exe or pwsh. Uses mocked AD queries and real CSV/index writers.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$moduleRoot = Split-Path -Parent $PSScriptRoot

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

foreach ($path in @(
    'Private\DiscoveryDiagnostics.ps1',
    'Private\DiscoveryTargeting.ps1',
    'Private\Resolve-AdPath.ps1',
    'Private\Invoke-AdDiscovery.ps1',
    'Private\New-ADDiscoveryIndex.ps1',
    'Private\Export-AdCsvSafeWithSchema.ps1',
    'Private\Resolve-AdSchemaNameForCsv.ps1',
    'Public\Export-AdCsvSafe.ps1',
    'Public\Get-AdSchemaDefinitions.ps1',
    'Public\Invoke-AdDiscoveryExport.ps1'
)) { . (Join-Path $moduleRoot $path) }

# Default unrelated collectors to no rows. Restore real user/computer collectors below.
$commands = (Get-Command Invoke-AdDiscovery).ScriptBlock.Ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst]
}, $true)
foreach ($name in @($commands | ForEach-Object { $_.GetCommandName() } |
    Where-Object { $_ -like 'Get-Ad*' } | Sort-Object -Unique)) {
    Set-Item -Path "Function:$name" -Value { }
}

foreach ($path in @(
    'Private\DiscoveryDiagnostics.ps1',
    'Private\DiscoveryTargeting.ps1',
    'Public\Get-AdAdUsers.ps1',
    'Public\Get-AdAdComputers.ps1',
    'Public\Get-AdAdGroups.ps1',
    'Public\Get-AdAdFineGrainedPasswordPolicies.ps1',
    'Public\Get-AdAdFineGrainedPasswordPolicyAssignments.ps1',
    'Public\Get-AdUserStatusDetails.ps1',
    'Public\Get-AdComputerStatusDetails.ps1',
    'Public\Get-AdGpoInventory.ps1',
    'Public\Get-AdAdOuDelegationAcls.ps1',
    'Public\Write-AdLog.ps1',
    'Private\Get-AdTimestamp.ps1',
    'Private\UserStatus-Helpers.ps1',
    'Private\ComputerStatus-Helpers.ps1',
    'Private\Get-AdUpnSuffix.ps1',
    'Private\Test-AdNonRoutableSuffix.ps1',
    'Private\ConvertFrom-AdFileTime.ps1',
    'Private\Get-AdDaysSince.ps1',
    'Private\Convert-AdEncryptionTypes.ps1',
    'Private\Get-AdEncryptionRisk.ps1',
    'Private\Get-AdComputerIsServer.ps1'
    'Private\Test-AdBuiltInGroup.ps1'
)) { . (Join-Path $moduleRoot $path) }

function Export-AdSchemas { }
function Get-AdAdForest {
    if ($scenario.Failure -eq 'ForestFailure') { throw 'Simulated forest startup failure' }
    [pscustomobject]@{ Name = 'example.test'; RootDomain = 'example.test' }
}
function Get-AdAdDomains { $scenario.Domains }
function Get-AdKnownUpnSuffixes { @{ 'example.test' = $true } }
function Get-AdAdDomainContext {
    param($DomainFqdn, $LogPath, $Server)
    $scenario.CurrentDomain = $DomainFqdn
    [pscustomobject]@{ DomainFqdn = $DomainFqdn; Server = ('dc.' + $DomainFqdn); DomainController = ('dc.' + $DomainFqdn); DomainDn = ('DC=' + ($DomainFqdn -replace '\.', ',DC=')) }
}
function Get-AdAdDomainSummary {
    if ($scenario.Failure -eq 'Earlier') { Write-Error 'Simulated domain summary failure' }
    [pscustomobject]@{
        DomainFqdn = $scenario.CurrentDomain; DomainDn = ('DC=' + ($scenario.CurrentDomain -replace '\.', ',DC='))
        NetBIOSName = 'EXAMPLE'; DomainMode = 'Windows2016Domain'; PdcEmulator = ('dc.' + $scenario.CurrentDomain)
        RidMaster = ('dc.' + $scenario.CurrentDomain); InfrastructureMaster = ('dc.' + $scenario.CurrentDomain)
        ServerUsed = ('dc.' + $scenario.CurrentDomain)
    }
}
function Get-ADGroup {
    [CmdletBinding()]
    param($Filter, $Server, $Properties, $SearchBase, $SearchScope)
    if ($scenario.Failure -eq 'Groups') { throw 'Simulated group collection failure' }
    [pscustomobject]@{
        Name = 'Sample group'; SamAccountName = 'SampleGroup'; DistinguishedName = ('CN=Sample,DC=' + ($scenario.CurrentDomain -replace '\.', ',DC='))
        GroupCategory = 'Security'; GroupScope = 'Global'; mail = ''; whenCreated = Get-Date; whenChanged = Get-Date
        Description = ''; SID = 'S-1-5-21-1-2-3-1100'
    }
}
function Get-ADFineGrainedPasswordPolicy {
    [CmdletBinding()]
    param($Filter, $Server, $SearchBase, $SearchScope)
    if ($scenario.Failure -eq 'FgppFailure') { throw 'Simulated FGPP query failure' }
    if ($scenario.Failure -eq 'FgppRows') {
        [pscustomobject]@{
            Name = 'Policy'; DistinguishedName = ('CN=Policy,DC=' + ($scenario.CurrentDomain -replace '\.', ',DC=')); Precedence = 1
            AppliesTo = @('CN=Sample,DC=example,DC=test'); ComplexityEnabled = $true; MinPasswordLength = 14
            PasswordHistoryCount = 24; MinPasswordAge = [timespan]::FromDays(1); MaxPasswordAge = [timespan]::FromDays(90)
            LockoutThreshold = 5; LockoutDuration = [timespan]::FromMinutes(15); LockoutObservationWindow = [timespan]::FromMinutes(15)
            ReversibleEncryptionEnabled = $false
        }
    }
}
function Get-ADUser {
    [CmdletBinding()]
    param($Filter, $Server, $Properties, $SearchBase, $SearchScope)
    if ($scenario.Failure -eq 'Retry' -and $Server -like 'dc.*') { throw 'Simulated first-server failure' }
    if ($scenario.Failure -eq 'Users' -and $scenario.CurrentDomain -eq $scenario.FailureDomain) {
        throw 'Simulated user collection failure'
    }
    if ($scenario.Empty) { return }
    $userDomain = if ($scenario.Failure -eq 'WrongDomainRows') { 'runner.test' } else { $scenario.CurrentDomain }
    [pscustomobject]@{
        SamAccountName = 'sample'; Name = 'Sample user'; DistinguishedName = ('CN=Sample,DC=' + ($userDomain -replace '\.', ',DC='))
        Enabled = $true; UserPrincipalName = 'sample@example.test'; Mail = 'sample@example.test'
        whenCreated = Get-Date; whenChanged = Get-Date; LastLogonTimestamp = 0; PasswordLastSet = $null
        adminCount = 0; SIDHistory = @(); ServicePrincipalName = @(); Description = ''
        'msDS-SupportedEncryptionTypes' = 4
    }
}
function Get-ADComputer {
    [CmdletBinding()]
    param($Filter, $Server, $Properties, $SearchBase, $SearchScope)
    if ($scenario.Failure -eq 'Computers') { throw 'Simulated computer collection failure' }
    if ($scenario.Empty) { return }
    [pscustomobject]@{
        Name = 'PC1'; SamAccountName = 'PC1$'; DistinguishedName = ('CN=PC1,DC=' + ($scenario.CurrentDomain -replace '\.', ',DC='))
        Enabled = $true; DNSHostName = 'pc1.example.test'; OperatingSystem = 'Windows 11'
        OperatingSystemVersion = ''; whenCreated = Get-Date; whenChanged = Get-Date
        LastLogonTimestamp = 0; ServicePrincipalName = @(); Description = ''
        'msDS-SupportedEncryptionTypes' = 8
    }
}
function Get-AdGroupMembershipDetails {
    [pscustomobject]@{ EmptyGroups = @(); SingleMemberGroups = @(); GroupsWithDisabledOrInactiveMembers = @() }
}
function Get-AdSecurityTier0Inventory {
    [pscustomobject]@{ PrivilegedGroupMembers = @(); AdminCountObjects = @(); ProtectedUsers = @() }
}
function Get-AdSecurityDelegationInventory {
    [pscustomobject]@{ Unconstrained = @(); Constrained = @(); ProtocolTransition = @(); RBCD = @() }
}
function Get-AdSecurityAdcsInventory {
    if ($scenario.Failure -eq 'Security') { throw 'Simulated ADCS collection failure' }
}
function Get-GPO {
    [CmdletBinding()]
    param([switch]$All, $Domain, $Server)
    if ($scenario.Failure -eq 'GpoFailure') { throw 'Simulated GPO query failure' }
}
function Get-ADOrganizationalUnit {
    [CmdletBinding()]
    param($Filter, $SearchBase, $SearchScope, $Server, $Properties)
    if ($scenario.Failure -eq 'OuPartial') {
        [pscustomobject]@{ Name = 'Readable'; DistinguishedName = 'OU=Readable,DC=example,DC=test' }
        [pscustomobject]@{ Name = 'Denied'; DistinguishedName = 'OU=Denied,DC=example,DC=test' }
    }
}
function Get-ADObject {
    [CmdletBinding()]
    param($Identity, $Server, $Properties)
    if ($Identity -like '*OU=Denied,*') { throw 'Simulated OU ACL access denied' }
    [pscustomobject]@{ nTSecurityDescriptor = [pscustomobject]@{ Access = @([pscustomobject]@{
        IsInherited = $false; IdentityReference = 'EXAMPLE\Delegates'; ActiveDirectoryRights = 'GenericRead'
        AccessControlType = 'Allow'; InheritanceType = 'All'; ObjectType = ''; InheritedObjectType = ''
    }) } }
}
function Get-Command {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name)
    if ($Name -eq 'Get-GPO' -and $scenario.Failure -eq 'GpoSkipped') { return }
    if ($Name -eq 'Get-ADFineGrainedPasswordPolicy' -and $scenario.Failure -eq 'FgppSkipped') { return }
    Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}
function New-AdRunLayout {
    param($OutputRoot, $Prefix, [switch]$CreateLog)
    if ($scenario.Failure -eq 'GroupExport') {
        $blocked = Join-Path $OutputRoot '20_domains\Domain-example.test\AD__Domain__Identity__Groups__Domain-example.test.csv'
        New-Item -ItemType Directory -Path $blocked -Force | Out-Null
    }
    if ($scenario.Failure -eq 'StatusExport') {
        New-Item -ItemType Directory -Path (Join-Path $OutputRoot '99_manifest\Run__ExecutionStatus__Run.csv') -Force | Out-Null
    }
    if ($scenario.Failure -eq 'IndexFailure') {
        New-Item -ItemType Directory -Path (Join-Path $OutputRoot '99_manifest\Discovery.Index.json') -Force | Out-Null
    }
    [pscustomobject]@{ RunRoot = $OutputRoot; LogPath = Join-Path $OutputRoot '90_logs\discovery.log' }
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AdDiscoveryRegression-' + [guid]::NewGuid().ToString('N'))
$cases = @('Healthy', 'Groups', 'Users', 'Computers', 'Earlier', 'GroupExport', 'MultiDomain', 'Security', 'Empty', 'StatusExport', 'Retry', 'GpoFailure', 'GpoSkipped', 'OuPartial', 'FgppRows', 'FgppFailure', 'FgppSkipped', 'WrongDomainRows')
foreach ($case in $cases) {
    $scenario = @{
        Failure = $case; Domains = @('example.test'); CurrentDomain = ''; FailureDomain = 'example.test'; Empty = $false
    }
    if ($case -eq 'MultiDomain') {
        $scenario.Failure = 'Users'
        $scenario.Domains = @('example.test', 'child.example.test')
        $scenario.FailureDomain = 'child.example.test'
    }
    if ($case -eq 'Empty') { $scenario.Empty = $true }
    $output = @(Invoke-AdDiscoveryExport -OutputRoot (Join-Path $testRoot $case) -IncludeSecurity:($case -eq 'Security') 3>&1 6>&1)
    $result = $output | Where-Object { $_.PSObject.Properties['RunRoot'] } | Select-Object -Last 1
    Assert-Condition ($null -ne $result) "$case returns a result"
    $expectedStatus = if ($case -in @('Healthy', 'Empty', 'Retry', 'FgppRows')) { 'Complete' } else { 'Partial' }
    Assert-Condition ($result.Status -eq $expectedStatus) "$case status is $expectedStatus"
    Assert-Condition (($output | Out-String).Contains('[OK] Discovery complete') -eq ($expectedStatus -eq 'Complete')) "$case completion message"
    Assert-Condition ($result.FailedOperationCount -eq @($result.FailedOperations).Count) "$case failure count"
    $expectedFailures = if ($case -in @('Healthy', 'Empty', 'Retry', 'GpoSkipped', 'OuPartial', 'FgppRows', 'FgppSkipped')) { 0 } elseif ($case -in @('Security', 'FgppFailure')) { 2 } else { 1 }
    Assert-Condition ($result.FailedOperationCount -eq $expectedFailures) "$case records only expected failures"
    $expectedUsers = if ($scenario.Empty) { 0 } else {
        @($scenario.Domains | Where-Object { -not ($scenario.Failure -in @('Users','WrongDomainRows') -and $_ -eq $scenario.FailureDomain) }).Count
    }
    $expectedComputers = if ($scenario.Empty -or $case -eq 'Computers') { 0 } else { $scenario.Domains.Count }
    $expectedGroups = if ($case -eq 'Groups') { 0 } else { $scenario.Domains.Count }
    Assert-Condition ($result.UserCount -eq $expectedUsers -and $result.ComputerCount -eq $expectedComputers -and $result.GroupCount -eq $expectedGroups) "$case totals reflect collected rows, including export failures and domain isolation"

    foreach ($domain in $scenario.Domains) {
        $domainDir = Join-Path $result.RunRoot ("20_domains\Domain-$domain")
        foreach ($dataset in @('Groups', 'Users', 'ComputersAll')) {
            $failed = ($case -eq 'Groups' -and $dataset -eq 'Groups') -or
                ($case -eq 'GroupExport' -and $dataset -eq 'Groups') -or
                ($scenario.Failure -in @('Users', 'WrongDomainRows') -and $domain -eq $scenario.FailureDomain -and $dataset -eq 'Users') -or
                ($case -eq 'Computers' -and $dataset -eq 'ComputersAll')
            $csv = Join-Path $domainDir ("AD__Domain__Identity__{0}__Domain-{1}.csv" -f $dataset, $domain)
            Assert-Condition ((Test-Path -LiteralPath $csv -PathType Leaf) -eq (-not $failed)) "$case $domain $dataset presence"
            if (-not $failed) {
                $rows = @(Import-Csv -LiteralPath $csv)
                $expectedRows = if ($scenario.Empty -and $dataset -ne 'Groups') { 0 } else { 1 }
                Assert-Condition ($rows.Count -eq $expectedRows) "$case $domain $dataset row count"
                if ($rows.Count -gt 0) { Assert-Condition ($rows[0].DomainFqdn -eq $domain) "$case $dataset domain isolation" }
            }
        }
        foreach ($detail in @('UsersDisabled', 'ComputersInactiveServers')) {
            $sourceFailed = ($detail -eq 'UsersDisabled' -and $scenario.Failure -in @('Users', 'WrongDomainRows') -and $domain -eq $scenario.FailureDomain) -or
                ($detail -eq 'ComputersInactiveServers' -and $case -eq 'Computers')
            $csv = Join-Path $domainDir ("AD__Domain__Identity__{0}__Domain-{1}.csv" -f $detail, $domain)
            Assert-Condition ((Test-Path -LiteralPath $csv -PathType Leaf) -eq (-not $sourceFailed)) "$case $domain $detail dependency"
        }
        $gpoPresent = Test-Path -LiteralPath (Join-Path $domainDir ("AD__Domain__GPO__Inventory__Domain-$domain.csv")) -PathType Leaf
        Assert-Condition ($gpoPresent -eq ($case -notin @('GpoFailure', 'GpoSkipped'))) "$case GPO output distinguishes failure from empty"
        Assert-Condition (Test-Path (Join-Path $domainDir ("AD__Domain__GPO__Links__Domain-$domain.csv"))) "$case later exports continue"
        foreach ($name in @('PasswordPolicyFgpp', 'PasswordPolicyFgppAssignments')) {
            $csv = Join-Path $domainDir ("AD__Domain__Security__{0}__Domain-{1}.csv" -f $name, $domain)
            $expected = $case -notin @('FgppFailure', 'FgppSkipped')
            Assert-Condition ((Test-Path -LiteralPath $csv -PathType Leaf) -eq $expected) "$case $name coverage"
            if ($expected) {
                $expectedRows = if ($case -eq 'FgppRows') { 1 } else { 0 }
                Assert-Condition (@(Import-Csv $csv).Count -eq $expectedRows) "$case $name rows"
            }
        }
    }

    if ($case -eq 'StatusExport') {
        Assert-Condition ($null -eq $result.ExecutionStatusPath) 'Failed status export returns no misleading path'
        Assert-Condition (@($result.FailedOperations | Where-Object { $_.Operation -eq 'Execution Status Export' }).Count -eq 1) 'Status export failure returned'
    } else {
        $failures = @(Import-Csv $result.ExecutionStatusPath | Where-Object { $_.Status -eq 'FAIL' })
        Assert-Condition ($failures.Count -eq $result.FailedOperationCount) "$case failures persisted"
    }
    if ($expectedFailures -gt 0) {
        Assert-Condition ($result.FailedOperationCount -gt 0) "$case exposes failures"
        Assert-Condition ((Get-Content $result.LogPath -Raw).Contains('FAIL')) "$case failure logged"
    }
    if ($case -in @('OuPartial', 'GpoSkipped')) {
        Assert-Condition ($result.IncompleteOperations.Count -gt 0) "$case exposes incomplete collection"
    }
    $events = @(Get-Content $result.DiagnosticLogPath | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Condition (@($events | Where-Object { $_.RunId -ne $result.RunId }).Count -eq 0) "$case run correlation"
    $metadata = ($events | Where-Object { $_.Operation -eq 'Run Context' } | Select-Object -First 1).Details | ConvertFrom-Json
    Assert-Condition ([bool]$metadata.PowerShellVersion -and [bool]$metadata.CollectorSha256) "$case runtime metadata"
    $started = @($events | Where-Object { $_.Kind -eq 'Operation' -and $_.Status -eq 'START' })
    foreach ($start in $started) {
        $ends = @($events | Where-Object { $_.Kind -eq 'Operation' -and $_.OperationId -eq $start.OperationId -and $_.Status -ne 'START' })
        Assert-Condition ($ends.Count -eq 1) "$case $($start.Operation) has one end event"
        Assert-Condition ($null -ne $ends[0].DurationMs -and [bool]$ends[0].EndedUtc) "$case operation duration"
    }
    if ($case -eq 'Healthy') {
        $usersEnd = $events | Where-Object { $_.Kind -eq 'Operation' -and $_.Operation -eq 'Users (example.test)' -and $_.Status -eq 'OK' }
        Assert-Condition ($usersEnd.RowCount -eq 1 -and [bool]$usersEnd.OutputPath) 'User export records row count and path'
    }
    if ($case -eq 'Empty') {
        Assert-Condition (@($events | Where-Object { $_.Kind -eq 'Operation' -and $_.Operation -eq 'Users (example.test)' -and $_.Status -eq 'EMPTY' }).Count -eq 1) 'Empty is distinct from failed'
    }
    if ($case -eq 'Retry') {
        $retry = @($events | Where-Object { $_.Kind -eq 'Query' -and $_.Status -eq 'RETRY' })
        Assert-Condition ($retry.Count -eq 1 -and [bool]$retry[0].ScriptStackTrace -and [bool]$retry[0].ErrorId) 'Recovered retry retains original error'
        Assert-Condition (@($events | Where-Object { $_.Kind -eq 'Query' -and $_.Status -eq 'OK' -and $_.Server -eq 'example.test' }).Count -gt 0) 'Retry stays explicitly in the requested domain'
    }
    foreach ($failure in $result.FailedOperations) {
        Assert-Condition ([bool]$failure.ExceptionType -and [bool]$failure.ErrorId -and [bool]$failure.ScriptStackTrace -and $failure.ScriptLineNumber -gt 0) "$case original error details retained"
    }
    $index = Get-Content (Join-Path $result.RunRoot '99_manifest\Discovery.Index.json') -Raw | ConvertFrom-Json
    Assert-Condition (@($index.datasets).Count -gt 0) "$case index generated"
    if ($case -ne 'StatusExport') {
        Assert-Condition (@($index.datasets | Where-Object { $_.path -like '*Run__ExecutionStatus__Run.csv' }).Count -eq 1) "$case execution status indexed"
    }
    foreach ($dataset in $index.datasets) {
        $actualHash = (Get-FileHash -LiteralPath (Join-Path $result.RunRoot $dataset.path) -Algorithm SHA256).Hash
        Assert-Condition ($actualHash -eq $dataset.sha256) "$case index hash for $($dataset.path)"
        if ($dataset.contentType -eq 'text/csv') {
            $actualRows = @(Import-Csv -LiteralPath (Join-Path $result.RunRoot $dataset.path)).Count
            Assert-Condition ($actualRows -eq $dataset.rows) "$case index row count for $($dataset.path)"
        }
    }
    Write-Host "PASS: $case"
}

foreach ($case in @('ForestFailure', 'IndexFailure')) {
    $scenario = @{ Failure = $case; Domains = @('example.test'); CurrentDomain = ''; FailureDomain = ''; Empty = $false }
    $runRoot = Join-Path $testRoot $case
    $thrown = $false
    try { $null = Invoke-AdDiscoveryExport -OutputRoot $runRoot 3>&1 6>&1 } catch { $thrown = $true }
    Assert-Condition $thrown "$case remains terminating"
    $jsonl = Get-ChildItem (Join-Path $runRoot '90_logs') -Filter *.jsonl | Select-Object -First 1
    $events = @(Get-Content $jsonl.FullName | ForEach-Object { $_ | ConvertFrom-Json })
    $operation = if ($case -eq 'ForestFailure') { 'Forest Discovery' } else { 'Discovery Index' }
    $failure = @($events | Where-Object { $_.Operation -eq $operation -and $_.Status -eq 'FAIL' })
    Assert-Condition ($failure.Count -eq 1 -and [bool]$failure[0].ScriptStackTrace) "$case persisted full error"
    Write-Host "PASS: $case diagnostics"
}

foreach ($entry in @(
    @{ Value = $null; Risk = 'Unknown' }, @{ Value = 0; Risk = 'Unknown' },
    @{ Value = 1; Risk = 'High' }, @{ Value = 2; Risk = 'High' },
    @{ Value = 4; Risk = 'Medium' }, @{ Value = 8; Risk = 'Low' },
    @{ Value = 16; Risk = 'Low' }, @{ Value = 24; Risk = 'Low' }, @{ Value = 28; Risk = 'Low' }
)) {
    Assert-Condition ((Get-AdEncryptionRisk -EncryptionTypeValue $entry.Value) -eq $entry.Risk) "Encryption risk for '$($entry.Value)'"
}
Write-Host "PASS: encryption risk cases; regression outputs: $testRoot"
