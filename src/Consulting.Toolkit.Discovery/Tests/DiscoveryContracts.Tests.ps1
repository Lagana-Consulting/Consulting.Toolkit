# Public API and producer -> schema -> CSV -> consumer integration checks.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$moduleRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $moduleRoot 'Consulting.Toolkit.Discovery.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$module = Import-Module $manifestPath -Force -PassThru -WarningAction SilentlyContinue
$actual = @(Get-Command -Module $module.Name | Select-Object -ExpandProperty Name)
if (@(Compare-Object @($manifest.FunctionsToExport) $actual).Count) { throw 'Imported API differs from the declared manifest.' }
foreach ($name in $manifest.FunctionsToExport) {
    if (-not (Get-Command ($module.Name + '\' + $name) -ErrorAction SilentlyContinue)) { throw "Export '$name' is not available to callers." }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('AdDiscoveryContracts-' + [guid]::NewGuid().ToString('N'))
$layout = New-AdRunLayout -OutputRoot $root -Prefix 'PublicAPI'
$written = @(Export-AdSchemas -SchemasDir $layout.SchemasDir -Include @('Users','SPNs'))
if ($written.Count -ne 2) { throw 'Public schema export failed.' }
$failed = $false
try { Export-AdSchemas -SchemasDir (Join-Path $root 'Unknown') -Include @('Users','UnknownContract') | Out-Null } catch { $failed = $true }
if (-not $failed -or (Test-Path (Join-Path $root 'Unknown'))) { throw 'Schema selection must validate every name before writing.' }
Write-Host 'PASS: manifest exports available outside module scope and public helpers execute'

& $module {
    param($Root)
    function Assert-Contract {
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }
    $producers=@{
    AdminSdHolderImpact='Get-AdAdminSdHolderImpact';Assessment_Summary='Get-AdAssessmentSummary';CertificateServices_Inventory='Get-AdCertificateServicesInventory';Computers='Get-AdAdComputers';ComputerStatus_InactiveServers='Get-AdComputerStatusDetails';ComputerStatus_InactiveWorkstations='Get-AdComputerStatusDetails';CrossDomainGroupMembership='Get-AdCrossDomainGroupMembership';Dhcp_ScopeAnalysis='Get-AdDhcpScopeAnalysis';DisabledAccounts='Get-AdDisabledAccounts';DnsZone_Inventory='Get-AdDnsZoneInventory';Domain_GPO_Delegation='Get-AdGpoDelegation';Domain_Security_AdminCountObjects='Get-AdAdminCountObjects';Domain_Security_AsrepRoastableUsers='Get-AdAsrepRoastableUsers';Domain_Security_BuiltInAdministratorSignals='Get-AdBuiltInAdministratorSignals';Domain_Security_DelegationConstrained='Get-AdDelegationConstrained';Domain_Security_DelegationProtocolTransition='Get-AdDelegationProtocolTransition';Domain_Security_DelegationRBCD='Get-AdDelegationRBCD';Domain_Security_DelegationUnconstrained='Get-AdDelegationUnconstrained';Domain_Security_DomainControllerSecuritySignals='Get-AdSecurityDomainControllerSignals';Domain_Security_PrivilegedGroupMembers='Get-AdPrivilegedGroupMembers';Domain_Security_PrivilegedPasswordAge='Get-AdPrivilegedPasswordAge';Domain_Security_ProtectedUsers='Get-AdProtectedUsersMembers';Domain_Security_RecentlyCreatedObjects='Get-AdRecentlyCreatedObjects';Domain_Security_SpnAccounts='Get-AdSpnAccounts';Domain_Summary='Get-AdAdDomainSummary';DuplicateSPNs='Get-AdDuplicateSpns';EmptyGroups='New-AdGroupMembershipSummaryRow';Forest_Security_ADCS_CertificateTemplatePermissions='Get-AdcsTemplatePermissions';Forest_Security_ADCS_CertificateTemplates='Get-AdcsCertificateTemplates';Forest_Security_ADCS_EnrollmentServicesTemplates='Get-AdcsEnrollmentServicesTemplatesFromConfigurationPartition';Forest_Security_ADCS_EnterpriseCAs='Get-AdcsEnterpriseCAsFromConfigurationPartition';Forest_Security_Trusts='Get-AdAdForestTrusts';Forest_Summary='Get-AdAdForestSummary';Forest_UPNSuffixes='Get-AdAdForestUpnSuffixes';FsmoRole_Availability='Get-AdFsmoRoleAvailability';Gpo_PerformanceAnalysis='Get-AdGpoPerformanceAnalysis';GroupMembership_DisabledOrInactiveMembers='Get-AdGroupMembershipMemberDetail';GroupMembership_EmptyGroups='New-AdGroupMembershipSummaryRow';GroupMembership_SingleMemberGroups='New-AdGroupMembershipSingleMemberRow';GroupNestingDepth='Get-AdGroupNestingDepth';Groups='Get-AdAdGroups';GroupToken_Bloat='Get-AdGroupTokenBloat';Migration_RiskFlags='Get-AdMigrationRiskFlags';Migration_RiskFlags_Summary='Get-AdMigrationRiskFlagsSummary';OuDepthAnalysis='Get-AdOuDepthAnalysis';PrivilegedAccounts='Get-AdPrivilegedAccounts';SiteLink_CostAnalysis='Get-AdSiteLinkCostAnalysis';SPNs='Get-AdAdSpns';Sysvol_SizeAnalysis='Get-AdSysvolSizeAnalysis';TombstoneLifetime='Get-AdTombstoneLifetime';TopSPNsByType='Get-AdTopSpnsByType';Trust_RelationshipMap='Get-AdTrustRelationshipMap';Users='Get-AdAdUsers';UserStatus_DisabledUsers='Get-AdUserStatusDetails';UserStatus_InactiveUsers='Get-AdUserStatusDetails';WeakPasswordPolicies='Get-AdWeakPasswordPolicies';GpoInventory='Get-AdGpoInventory';Forest_Sites='Get-AdAdReplicationSites';Forest_Subnets='Get-AdAdReplicationSubnets';Forest_SiteLinks='Get-AdAdReplicationSiteLinks'
    }

    $defs = Get-AdSchemaDefinitions
    Assert-Contract (@(Compare-Object @($defs.Keys) @($producers.Keys)).Count -eq 0) 'Every registered schema has a producer audit'
    foreach ($key in $defs.Keys) {
        $columns = @($defs[$key] | ForEach-Object Column)
        Assert-Contract (@($columns | Sort-Object -Unique).Count -eq $columns.Count) "$key has unique columns"
        $tables = @((Get-Command $producers[$key]).ScriptBlock.Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ConvertExpressionAst] -and
            $node.Type.TypeName.FullName -eq 'pscustomobject' -and
            $node.Child -is [System.Management.Automation.Language.HashtableAst]
        }, $true))
        $matched = $false
        foreach ($table in $tables) {
            $fields = @($table.Child.KeyValuePairs | ForEach-Object { $_.Item1.Value })
            if (@(Compare-Object $columns $fields).Count -eq 0) { $matched = $true; break }
        }
        Assert-Contract $matched "$key columns match a real producer row, with no missing or dropped fields"
    }
    $resolver = (Get-Command Resolve-AdSchemaNameForCsv).ScriptBlock.Ast
    $maps = @($resolver.FindAll({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $true))
    foreach ($map in $maps) {
        $entry = $map.SafeGetValue()
        Assert-Contract ($defs.ContainsKey($entry.Schema)) "Filename mapping resolves to schema $($entry.Schema)"
    }
    Write-Host "PASS: all $($defs.Count) registered schemas agree with their producer shapes and all filename mappings resolve"

    $state = @{ Count = 0; Version = 50 }
    $domain = 'example.test'
    $ctx = [pscustomobject]@{
        DomainFqdn = $domain; DomainDn = 'DC=example,DC=test'; Server = 'dc.example.test'
        NetBIOSName = 'EXAMPLE'; DomainMode = 'Windows2016Domain'; PdcEmulator = 'dc.example.test'
        RidMaster = 'dc.example.test'; InfrastructureMaster = 'dc.example.test'
    }
    $passwordTime = [datetime]::SpecifyKind([datetime]'2024-01-02T03:04:05', [DateTimeKind]::Utc)
    $forest = [pscustomobject]@{ Name=$domain; RootDomain=$domain; ForestMode='Windows2016Forest'; Domains=@($domain); UPNSuffixes=@('mail.example.test'); SchemaMaster=$ctx.Server; DomainNamingMaster=$ctx.Server }
    function Get-ADForest { [CmdletBinding()] param($Identity,$Server); $forest }
    function New-DirectoryRows {
        for ($i=1; $i -le $state.Count; $i++) {
            $spns = if ($state.Count -eq 1) { @('HTTP/unique') } else { @('HTTP/shared', ('HOST/owner' + $i)) }
            [pscustomobject]@{
                Name=('Owner'+$i); SamAccountName=('owner'+$i); DistinguishedName=("CN=Owner$i,DC=example,DC=test")
                ObjectClass='user'; Enabled=($i -eq 1); userAccountControl=if($i -eq 1){512}else{514}
                UserPrincipalName=("owner$i@example.test"); Mail=''; whenCreated=$passwordTime; whenChanged=$passwordTime
                LastLogonTimestamp=$passwordTime.ToFileTimeUtc(); PasswordLastSet=if($i -eq 1){$passwordTime}else{$null}
                pwdLastSet=if($i -eq 1){$passwordTime.ToFileTimeUtc()}else{0}; adminCount=1; SIDHistory=@()
                ServicePrincipalName=$spns; 'msDS-SupportedEncryptionTypes'=24
                Description="Line one, `"quoted`"`nLine two"
            }
        }
    }
    function Get-ADObject {
        [CmdletBinding()] param($LDAPFilter,$Filter,$SearchBase,$SearchScope,$Server,$Properties,$Identity)
        New-DirectoryRows
    }
    function Get-ADUser {
        [CmdletBinding()] param($Filter,$LDAPFilter,$SearchBase,$SearchScope,$Server,$Properties)
        New-DirectoryRows
    }
    function Get-ADComputer {
        [CmdletBinding()] param($Filter,$SearchBase,$SearchScope,$Server,$Properties)
        foreach ($row in @(New-DirectoryRows)) {
            [pscustomobject]@{
                Name=$row.Name; SamAccountName=($row.SamAccountName+'$'); DistinguishedName=$row.DistinguishedName
                Enabled=$row.Enabled; DnsHostName=($row.Name+'.example.test'); OperatingSystem='Windows 11'
                OperatingSystemVersion='10.0'; whenCreated=$passwordTime; whenChanged=$passwordTime
                LastLogonTimestamp=$passwordTime.ToFileTimeUtc(); ServicePrincipalName=$row.ServicePrincipalName
                'msDS-SupportedEncryptionTypes'=24; Description=$row.Description
            }
        }
    }
    function Get-ADGroup {
        [CmdletBinding()] param($Identity,$Filter,$Server,$SearchBase,$SearchScope,$Properties)
        if ($Identity) {
            if ($state.Count -eq 0) {
                $errorRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Absent group'), 'Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Identity)
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            [pscustomobject]@{ Name=$Identity; DistinguishedName=("CN=$Identity,DC=example,DC=test") }
            return
        }
        for ($i=1; $i -le $state.Count; $i++) {
            [pscustomobject]@{
                Name=('Group'+$i); SamAccountName=('group'+$i); DistinguishedName=("CN=Group$i,DC=example,DC=test")
                GroupCategory='Security'; GroupScope='Global'; Mail=''; whenCreated=$passwordTime; whenChanged=$passwordTime
                Description=''; SID=('S-1-5-21-1-2-3-'+(1100+$i)); Members=@()
            }
        }
    }
    function Get-ADGroupMember { [CmdletBinding()] param($Identity,$Server); New-DirectoryRows }
    function Get-GPO {
        [CmdletBinding()] param([switch]$All,$Domain,$Server)
        for ($i=1; $i -le $state.Count; $i++) {
            [pscustomobject]@{
                DisplayName=('Policy'+$i); Id=[guid](('00000000-0000-0000-0000-{0:d12}' -f $i))
                Owner='EXAMPLE\Admins'; CreationTime=$passwordTime; ModificationTime=$passwordTime; GpoStatus='AllSettingsEnabled'
                Description=''; User=[pscustomobject]@{DSVersion=$state.Version}; Computer=[pscustomobject]@{DSVersion=$state.Version}; WmiFilter=$null
            }
        }
    }
    function Test-CsvContract {
        param($Schema, [AllowEmptyCollection()][object[]]$Rows, $Path)
        $columns = @($defs[$Schema] | ForEach-Object Column)
        foreach ($row in $Rows) { Assert-Contract (@(Compare-Object $columns @($row.PSObject.Properties.Name)).Count -eq 0) "$Schema live rows match schema" }
        $Rows | Export-AdCsvSafe -Path $Path -SchemaName $Schema -AllowEmpty -Force | Out-Null
        $header = Get-Content -LiteralPath $Path -TotalCount 1
        Assert-Contract ($header -eq ('"' + ($columns -join '","') + '"')) "$Schema header is stable, including empty exports"
        $imported = @(Import-Csv -LiteralPath $Path)
        Assert-Contract ($imported.Count -eq $Rows.Count) "$Schema row count survives export/import"
        return $imported
    }
    foreach ($count in @(0,1,2)) {
        $state.Count = $count
        $folder = Join-Path $Root ("Rows$count [CSV]")
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $users = @(Get-AdAdUsers -DomainContext $ctx -Now ([datetime]'2026-01-01'))
        $computers = @(Get-AdAdComputers -DomainContext $ctx -Now ([datetime]'2026-01-01'))
        $groups = @(Get-AdAdGroups -DomainContext $ctx)
        $csvUsers = @(Test-CsvContract 'Users' $users (Join-Path $folder 'Users.csv'))
        $csvComputers = @(Test-CsvContract 'Computers' $computers (Join-Path $folder 'Computers.csv'))
        $null = Test-CsvContract 'Groups' $groups (Join-Path $folder 'Groups.csv')
        $null = Test-CsvContract 'PrivilegedAccounts' @(Get-AdPrivilegedAccounts -DomainContext $ctx) (Join-Path $folder 'Privileged.csv')
        $null = Test-CsvContract 'EmptyGroups' @(Get-AdEmptyGroups -DomainContext $ctx) (Join-Path $folder 'EmptyGroups.csv')
        $spns = @(Get-AdAdSpns -DomainContext $ctx)
        $csvSpns = @(Test-CsvContract 'SPNs' $spns (Join-Path $folder 'SPNs.csv'))
        foreach ($row in $csvSpns) {
            Assert-Contract ($row.ServicePrincipalName -eq $row.SPN) 'Canonical and legacy SPN fields agree'
            Assert-Contract ($row.ObjectClass -eq 'user' -and $row.ObjectType -eq 'User') 'Canonical and legacy object type fields agree'
        }
        $duplicateRows = @(Get-AdDuplicateSpns -DomainContext $ctx -Spns $csvSpns)
        $expectedDuplicates = if ($count -gt 1) {1} else {0}
        Assert-Contract ($duplicateRows.Count -eq $expectedDuplicates) 'SPN consumers identify true distinct-owner duplicates'
        if ($duplicateRows.Count) { Assert-Contract ($duplicateRows[0].ServicePrincipalName -eq 'HTTP/shared' -and $duplicateRows[0].ConflictCount -eq 2) 'Duplicate SPN identity and owners retained' }
        $null = Test-CsvContract 'DuplicateSPNs' $duplicateRows (Join-Path $folder 'Duplicates.csv')
        $top = @(Get-AdTopSpnsByType -DomainContext $ctx -Spns $csvSpns)
        $null = Test-CsvContract 'TopSPNsByType' $top (Join-Path $folder 'TopSPNs.csv')
        $security = @(Get-AdSpnAccounts -DomainContext $ctx)
        $securityCsv = @(Test-CsvContract 'Domain_Security_SpnAccounts' $security (Join-Path $folder 'SecuritySPNs.csv'))
        if ($count) {
            Assert-Contract ($securityCsv[0].Enabled -eq 'True' -and $securityCsv[0].PasswordLastSetUtc -eq $passwordTime.ToString('o')) 'SPN security facts collected from UAC and pwdLastSet'
            Assert-Contract ($csvUsers[0].Description -eq $users[0].Description) 'Quoted multiline fields survive CSV round trip'
        }
        if ($count -gt 1) { Assert-Contract ($securityCsv[1].Enabled -eq 'False' -and $securityCsv[1].PasswordLastSetUtc -eq '') 'Disabled and unknown password dates are preserved' }
        $userStatus = Get-AdUserStatusDetails -Users $csvUsers
        $computerStatus = Get-AdComputerStatusDetails -Computers $csvComputers
        $null = Test-CsvContract 'UserStatus_DisabledUsers' @($userStatus.DisabledUsers) (Join-Path $folder 'Disabled.csv')
        $null = Test-CsvContract 'ComputerStatus_InactiveWorkstations' @($computerStatus.InactiveWorkstations) (Join-Path $folder 'InactivePCs.csv')
        $gpos = @(Get-AdGpoInventory -DomainContext $ctx)
        $csvGpos = @(Test-CsvContract 'GpoInventory' $gpos (Join-Path $folder 'GPOs.csv'))
        Assert-Contract (@(Get-AdGpoPerformanceAnalysis -AllGpos $csvGpos).Count -eq 0) 'Version strings from CSV use numeric addition, not concatenation'
        $summary = Get-AdAssessmentSummary -ForestName $domain -AllUsers $csvUsers -AllComputers $csvComputers -AllGroups $groups -PrivilegedAccounts @()
        Assert-Contract ($summary.UsersTotal -eq $count) 'Assessment accepts exported user rows and empty inventories'
        $null = Test-CsvContract 'Assessment_Summary' @($summary) (Join-Path $folder 'Summary.csv')
        $flags = @(Get-AdMigrationRiskFlags -AllUsers $csvUsers -AllComputers $csvComputers)
        $null = Test-CsvContract 'Migration_RiskFlags' $flags (Join-Path $folder 'Flags.csv')
        $null = Test-CsvContract 'Migration_RiskFlags_Summary' @(Get-AdMigrationRiskFlagsSummary -RiskFlagsData $flags) (Join-Path $folder 'FlagSummary.csv')
        Write-Host "PASS: $count-row collectors -> schemas -> CSV -> consumers, including multiline values and bracketed paths"
    }
    $state.Count=1; $state.Version=600
    $highGpos = @(Get-AdGpoInventory -DomainContext $ctx)
    $highCsv = @(Test-CsvContract 'GpoInventory' $highGpos (Join-Path $Root 'HighGPOs.csv'))
    $performance = @(Get-AdGpoPerformanceAnalysis -AllGpos $highCsv)
    Assert-Contract ($performance.Count -eq 1 -and $performance[0].TotalVersions -eq 1200 -and $performance[0].GpoId -eq $highCsv[0].Id) 'GPO inventory DS versions and identifiers reach analysis correctly'
    $null = Test-CsvContract 'Gpo_PerformanceAnalysis' $performance (Join-Path $Root 'Performance.csv')
    $legacy = @([pscustomobject]@{SPN='HTTP/one';SamAccountName='one';DistinguishedName='CN=one'}, [pscustomobject]@{SPN='HTTP/two';SamAccountName='two';DistinguishedName='CN=two'})
    Assert-Contract (@(Get-AdDuplicateSpns -DomainContext $ctx -Spns $legacy).Count -eq 0) 'Legacy distinct SPNs cannot produce a blank-name false duplicate'
    $sameOwner = @($legacy[0],$legacy[0])
    Assert-Contract (@(Get-AdDuplicateSpns -DomainContext $ctx -Spns $sameOwner).Count -eq 0) 'Repeated rows for a single owner are not conflicts'
    $failed=$false
    try { Get-AdDuplicateSpns -DomainContext $ctx -Spns @([pscustomobject]@{Name='MissingSPN';SamAccountName='x';DistinguishedName='CN=x'}) | Out-Null } catch {$failed=$true}
    Assert-Contract $failed 'Malformed SPN rows fail instead of producing false findings'
    $validPath = Join-Path $Root 'Validated.csv'
    $state.Count=1
    $valid = @(Get-AdAdUsers -DomainContext $ctx)
    $null = Test-CsvContract 'Users' $valid $validPath
    $hash = (Get-FileHash -LiteralPath $validPath).Hash
    $failed=$false
    try { [pscustomobject]@{SamAccountName='MissingColumns'} | Export-AdCsvSafe -Path $validPath -SchemaName Users -Force | Out-Null } catch {$failed=$true}
    Assert-Contract ($failed -and (Get-FileHash -LiteralPath $validPath).Hash -eq $hash) 'Schema drift fails before overwriting an existing file'
    $autoPath = Join-Path $Root 'AD__Domain__Identity__Users__Domain-example.test.csv'
    @() | Export-AdCsvSafe -Path $autoPath -AllowEmpty -Force | Out-Null
    Assert-Contract ((Get-Content -LiteralPath $autoPath -TotalCount 1) -like '*SamAccountName*') 'Known filenames resolve schemas and create empty headers automatically'
    $upn = @(Get-AdAdForestUpnSuffixes -Forest $forest -Domains @($domain))
    $null = Test-CsvContract 'Forest_UPNSuffixes' $upn (Join-Path $Root 'Suffixes.csv')
    Assert-Contract ($upn[0].ForestName -eq $domain) 'Forest UPN schema includes the forest label'
    Write-Host "PASS: GPO contracts, legacy aliases, strict schema checks, empty headers, and forest UPN labels; outputs: $Root"
} $root

