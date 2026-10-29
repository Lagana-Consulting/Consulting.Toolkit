# Regression checks against real module collectors with mocked directory cmdlets.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Consulting.Toolkit.Discovery.psd1'
$module = Import-Module $modulePath -Force -PassThru -WarningAction SilentlyContinue
$root = Join-Path ([IO.Path]::GetTempPath()) ('AdDiscoveryTargetTests-' + [guid]::NewGuid().ToString('N'))
if (-not ('DiscoveryRegression.ADIdentityNotFoundException' -as [type])) {
    Add-Type 'namespace DiscoveryRegression { public class ADIdentityNotFoundException : System.Exception { public ADIdentityNotFoundException(string message) : base(message) {} } }'
}

& $module {
    param($Root)
    function Assert-Target {
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }
    $state = @{
        Mode = ''; Calls = New-Object System.Collections.Generic.List[object]
        Child = 'child.example.test'; ChildDn = 'DC=child,DC=example,DC=test'; RootDn = 'DC=example,DC=test'
    }
    $ctx = [pscustomobject]@{
        DomainFqdn = $state.Child; DomainDn = $state.ChildDn
        Server = 'failed.child.example.test'; DomainController = 'failed.child.example.test'
    }
    $forest = [pscustomobject]@{
        Name = 'example.test'; RootDomain = 'example.test'; SchemaMaster = 'unreachable.example.test'
        Domains = @('example.test', 'child.example.test'); UPNSuffixes = @()
    }
    function Trace-Query {
        param($Command, $Server, $SearchBase, $Identity)
        $state.Calls.Add([pscustomobject]@{ Command = $Command; Server = $Server; SearchBase = $SearchBase; Identity = $Identity })
    }
    function Get-ADForest {
        [CmdletBinding()] param($Server, $Identity)
        Trace-Query 'Get-ADForest' $Server '' $Identity
        $forest
    }
    function Get-ADDomain {
        [CmdletBinding()] param($Identity, $Server)
        Trace-Query 'Get-ADDomain' $Server '' $Identity
        $dns = if ($state.Mode -eq 'ContextForeign') { 'runner.test' } else { $Identity }
        [pscustomobject]@{
            DNSRoot = $dns; DistinguishedName = ('DC=' + ($dns -replace '\.', ',DC=')); NetBIOSName = 'TEST'
            DomainMode = 'Windows2016Domain'; PDCEmulator = $Server; RIDMaster = $Server; InfrastructureMaster = $Server
            Forest = 'example.test'
        }
    }
    function Get-ADRootDSE {
        [CmdletBinding()] param($Server)
        Trace-Query 'Get-ADRootDSE' $Server '' ''
        [pscustomobject]@{
            defaultNamingContext = if ($Server -like '*child.example.test') { $state.ChildDn } else { $state.RootDn }
            configurationNamingContext = 'CN=Configuration,DC=example,DC=test'
            schemaNamingContext = 'CN=Schema,CN=Configuration,DC=example,DC=test'
            rootDomainNamingContext = $state.RootDn
        }
    }
    function Get-ADUser {
        [CmdletBinding()] param($Filter, $LDAPFilter, $Server, $SearchBase, $SearchScope, $Properties, $Identity)
        Trace-Query 'Get-ADUser' $Server $SearchBase $Identity
        if ($state.Mode -eq 'Failover' -and $Server -eq $ctx.Server) { Write-Error 'Selected DC is unavailable' -Category ResourceUnavailable; return }
        if ($state.Mode -eq 'PasswordAgePartial') { Write-Error 'Password age access denied' -Category PermissionDenied; return }
        $dn = if ($state.Mode -eq 'ForeignRows' -or -not $Server) { 'CN=Runner,DC=runner,DC=test' } else { 'CN=User,' + $state.ChildDn }
        [pscustomobject]@{
            Name = 'User'; SamAccountName = 'User'; DistinguishedName = $dn; Enabled = $true
            UserPrincipalName = 'user@child.example.test'; Mail = ''; whenCreated = Get-Date; whenChanged = Get-Date
            LastLogonTimestamp = 0; PasswordLastSet = $null; adminCount = 0; SIDHistory = @(); ServicePrincipalName = @()
            'msDS-SupportedEncryptionTypes' = 24; Description = ''
        }
    }
    function Get-ADGroup {
        [CmdletBinding()] param($Identity, $Server, $Filter, $SearchBase, $SearchScope, $Properties)
        Trace-Query 'Get-ADGroup' $Server $SearchBase $Identity
        if ($state.Mode -in @('PrivilegedDenied', 'ProtectedDenied')) { Write-Error 'Group access denied' -Category PermissionDenied; return }
        if ($state.Mode -eq 'GroupMissing') { throw (New-Object DiscoveryRegression.ADIdentityNotFoundException('Group is absent')) }
        [pscustomobject]@{
            Name = 'ReviewGroup'; SamAccountName = 'ReviewGroup'; DistinguishedName = ('CN=ReviewGroup,' + $state.ChildDn)
            GroupCategory = 'Security'; GroupScope = 'Global'; SID = 'S-1-5-21-1-2-3-1100'
            whenCreated = Get-Date; whenChanged = Get-Date; Description = ''
            Members = @(('CN=Denied,' + $state.ChildDn), ('CN=Disabled,' + $state.ChildDn))
        }
    }
    function Get-ADGroupMember {
        [CmdletBinding()] param($Identity, $Server, [switch]$Recursive)
        Trace-Query 'Get-ADGroupMember' $Server '' $Identity
        if ($Identity -like 'CN=Denied,*') { Write-Error 'Nested group access denied' -Category PermissionDenied; return }
        [pscustomobject]@{ objectClass = 'user'; SamAccountName = 'Readable'; DistinguishedName = ('CN=Readable,' + $state.ChildDn) }
        [pscustomobject]@{ objectClass = 'group'; SamAccountName = 'Denied'; DistinguishedName = ('CN=Denied,' + $state.ChildDn) }
    }
    function Get-ADObject {
        [CmdletBinding()] param($Identity, $LDAPFilter, $Filter, $SearchBase, $SearchScope, $Server, $Properties)
        Trace-Query 'Get-ADObject' $Server $SearchBase $Identity
        if ($state.Mode -in @('AdminDenied','SpnDenied','EnterpriseCaDenied','EnrollmentDenied','TemplatesDenied','TemplateEnumerationDenied','ContactsSchemaDenied','DnsDenied','DhcpDenied','LegacyCertificateDenied')) {
            Write-Error 'Directory access denied' -Category PermissionDenied
            return
        }
        if ($state.Mode -eq 'TemplatePermissionsPartial') {
            if ($SearchBase) {
                [pscustomobject]@{ Name = 'Readable'; DistinguishedName = 'CN=Readable,CN=Certificate Templates,CN=Configuration,DC=example,DC=test' }
                [pscustomobject]@{ Name = 'Denied'; DistinguishedName = 'CN=Denied,CN=Certificate Templates,CN=Configuration,DC=example,DC=test' }
            } elseif ($Identity -like 'CN=Denied,*') {
                Write-Error 'Template ACL access denied' -Category PermissionDenied
            } else {
                [pscustomobject]@{ nTSecurityDescriptor = [pscustomobject]@{ Access = @([pscustomobject]@{
                    IdentityReference = [pscustomobject]@{ Value = 'S-1-5-11' }; ActiveDirectoryRights = 'ReadProperty'
                    AccessControlType = 'Allow'; IsInherited = $false
                }) } }
            }
            return
        }
        if ($state.Mode -eq 'MemberLookupPartial') {
            if ($Identity -like 'CN=Denied,*') { Write-Error 'Member lookup access denied' -Category PermissionDenied; return }
            [pscustomobject]@{
                Name = 'Disabled'; SamAccountName = 'Disabled'; ObjectClass = 'user'; DistinguishedName = $Identity
                userAccountControl = 514; LastLogonTimestamp = 0; Description = ''
            }
            return
        }
        if ($state.Mode -in @('Contacts', 'ContactsForeign') -and $LDAPFilter -eq '(objectClass=contact)') {
            $dn = if ($state.Mode -eq 'ContactsForeign') { 'CN=Contact,DC=runner,DC=test' } else { 'CN=Contact,' + $state.ChildDn }
            [pscustomobject]@{ Name = 'Contact'; DistinguishedName = $dn }
        }
    }
    function Get-ADReplicationSite { [CmdletBinding()] param($Filter,$Server); Trace-Query 'Get-ADReplicationSite' $Server '' '' }
    function Get-ADReplicationSubnet { [CmdletBinding()] param($Filter,$Server); Trace-Query 'Get-ADReplicationSubnet' $Server '' '' }
    function Get-ADReplicationSiteLink { [CmdletBinding()] param($Filter,$Server); Trace-Query 'Get-ADReplicationSiteLink' $Server '' '' }
    function Get-ADTrust { [CmdletBinding()] param($Filter,$Server); Trace-Query 'Get-ADTrust' $Server '' '' }
    function Get-AdPrivilegedAccounts { [pscustomobject]@{ DistinguishedName = ('CN=Privileged,' + $state.ChildDn) } }
    function Test-Path {
        [CmdletBinding()] param($Path, $LiteralPath)
        if ($state.Mode -eq 'SysvolDenied' -and $Path -like '\\*') { return $true }
        Microsoft.PowerShell.Management\Test-Path @PSBoundParameters
    }
    function Get-ChildItem {
        [CmdletBinding()] param($Path, [switch]$Recurse, [switch]$File, [switch]$Directory)
        if ($state.Mode -eq 'SysvolDenied') { Write-Error 'SYSVOL subtree access denied' -Category PermissionDenied; return }
        Microsoft.PowerShell.Management\Get-ChildItem @PSBoundParameters
    }

    function Invoke-CollectorProbe {
        param($Mode, [scriptblock]$Action, $Expected)
        $state.Mode = $Mode
        $state.Calls.Clear()
        $adDiscoveryLogContext = New-AdDiscoveryDiagnostics -OutputRoot (Join-Path $Root $Mode)
        $adDiscoveryLogContext.Domain = $state.Child
        $adDiscoveryLogContext.Server = $ctx.Server
        Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation $Mode -Status START
        $rows = @(); $failure = $null
        try {
            $rows = @(& $Action)
            Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation $Mode -Status OK
        } catch {
            $failure = $_
            Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation $Mode -Status FAIL -ErrorRecord $_
        }
        $outcome = Get-AdDiscoveryOutcome -Context $adDiscoveryLogContext
        $status = if ($Expected -eq 'Complete') { 'Complete' } else { 'Partial' }
        Assert-Target ($outcome.Status -eq $status) "$Mode has status $status"
        Assert-Target (($null -ne $failure) -eq ($Expected -eq 'Failure')) "$Mode terminating failure classification"
        Assert-Target (@($state.Calls | Where-Object { -not $_.Server }).Count -eq 0) "$Mode never queries an implicit server"
        if ($Expected -eq 'Partial') {
            Assert-Target ($outcome.IncompleteOperations.Count -gt 0) "$Mode preserves incomplete coverage"
            Assert-Target (@($adDiscoveryLogContext.Events | Where-Object { $_.Status -eq 'PARTIAL' -and $_.ErrorId -and $_.ScriptStackTrace }).Count -gt 0) "$Mode retains original partial errors"
        }
        Write-Host "PASS: $Mode"
        [pscustomobject]@{ Rows = $rows; Outcome = $outcome; Events = $adDiscoveryLogContext.Events.ToArray(); Calls = $state.Calls.ToArray() }
    }

    $probe = Invoke-CollectorProbe 'Failover' { Get-AdAdUsers -DomainContext $ctx } 'Complete'
    Assert-Target ($probe.Rows.Count -eq 1 -and $probe.Rows[0].DistinguishedName -like '*DC=child,DC=example,DC=test') 'Failover retains requested domain'
    Assert-Target (@($probe.Calls | Where-Object { $_.Command -eq 'Get-ADUser' -and $_.Server -eq $state.Child -and $_.SearchBase -eq $state.ChildDn }).Count -eq 1) 'Failover is explicitly targeted and anchored'
    $null = Invoke-CollectorProbe 'ForeignRows' { Get-AdAdUsers -DomainContext $ctx } 'Failure'
    $null = Invoke-CollectorProbe 'ChildAsParent' {
        Invoke-AdDiscoveryQuery -Operation 'Wrong partition' -Server 'dc.example.test' -DomainFqdn 'example.test' -ExpectedDomainDn $state.RootDn -Query {
            param($queryServer)
            [pscustomobject]@{ DistinguishedName = ('CN=Child,' + $state.ChildDn) }
        }
    } 'Failure'
    foreach ($dn in @('CN=Escaped\,DC=NotADomain,OU=Users,DC=child,DC=example,DC=test', 'CN=Trailing\\,DC=child,DC=example,DC=test')) {
        Assert-Target ((Get-AdDiscoveryDomainDn $dn) -eq $state.ChildDn) 'Escaped DN validation'
    }
    $probe = Invoke-CollectorProbe 'ContextFailover' { Get-AdAdDomainContext -DomainFqdn $state.Child -Server 'dc.example.test' } 'Complete'
    Assert-Target ($probe.Rows[0].Server -eq $state.Child) 'Root-domain DC is not reused for child inventory'
    $null = Invoke-CollectorProbe 'ContextForeign' { Get-AdAdDomainContext -DomainFqdn $state.Child -Server $ctx.Server } 'Failure'
    $probe = Invoke-CollectorProbe 'Contacts' { Get-AdAdContacts -DomainName $state.Child -Server 'dc.child.example.test' } 'Complete'
    Assert-Target ($probe.Rows.Count -eq 1) 'Contacts returned from requested domain'
    Assert-Target (@($probe.Calls | Where-Object { $_.Command -eq 'Get-ADObject' -and $_.SearchBase -eq $state.ChildDn }).Count -eq 1) 'Contacts use requested search base'
    Assert-Target (@($probe.Calls | Where-Object { $_.Server -ne 'dc.child.example.test' }).Count -eq 0) 'Contact schema and object reads use the selected DC'
    $null = Invoke-CollectorProbe 'ContactsForeign' { Get-AdAdContacts -DomainName $state.Child -Server 'dc.child.example.test' } 'Failure'
    $null = Invoke-CollectorProbe 'ContactsSchemaDenied' { Get-AdAdContacts -DomainName $state.Child -Server 'dc.child.example.test' } 'Failure'

    foreach ($case in @(
        @{ Mode='AdminDenied'; Action={ Get-AdAdminCountObjects -DomainContext $ctx } },
        @{ Mode='SpnDenied'; Action={ Get-AdSpnAccounts -DomainContext $ctx } },
        @{ Mode='PrivilegedDenied'; Action={ Get-AdPrivilegedGroupMembers -DomainContext $ctx } },
        @{ Mode='ProtectedDenied'; Action={ Get-AdProtectedUsersMembers -DomainContext $ctx } },
        @{ Mode='EnterpriseCaDenied'; Action={ Get-AdSecurityAdcsInventory -Forest $forest -Server 'selected.example.test' -Mode EnterpriseCAs } },
        @{ Mode='EnrollmentDenied'; Action={ Get-AdSecurityAdcsInventory -Forest $forest -Server 'selected.example.test' -Mode EnrollmentServicesTemplates } },
        @{ Mode='TemplatesDenied'; Action={ Get-AdSecurityCertificateTemplates -Forest $forest -Server 'selected.example.test' -Mode Templates } },
        @{ Mode='TemplateEnumerationDenied'; Action={ Get-AdSecurityCertificateTemplates -Forest $forest -Server 'selected.example.test' -Mode TemplatePermissions } }
    )) { $null = Invoke-CollectorProbe $case.Mode $case.Action 'Failure' }
    $probe = Invoke-CollectorProbe 'GroupMissing' { Get-AdProtectedUsersMembers -DomainContext $ctx } 'Complete'
    Assert-Target ($probe.Rows.Count -eq 0) 'Genuine missing group is distinct from access denied'
    $remoteMissing = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Remote missing group'), 'ActiveDirectoryCmdlet:Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException,Microsoft.ActiveDirectory.Management.Commands.GetADGroup', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
    Assert-Target (Test-AdDiscoveryIdentityNotFound $remoteMissing) 'Remoted AD identity-not-found errors remain recognizable'
    $remoteDenied = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Remote access denied'), 'ActiveDirectoryServer:5,Microsoft.ActiveDirectory.Management.Commands.GetADGroup', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
    Assert-Target (-not (Test-AdDiscoveryIdentityNotFound $remoteDenied)) 'Remoted permission errors are never classified as missing groups'
    $probe = Invoke-CollectorProbe 'RecursivePartial' { Get-AdGroupMembersRecursive -GroupDn ('CN=Root,' + $state.ChildDn) -Server $ctx.Server } 'Partial'
    Assert-Target ($probe.Rows.Count -eq 1) 'Readable recursive members retained'
    $probe = Invoke-CollectorProbe 'MemberLookupPartial' { Get-AdGroupMembershipDetails -DomainContext $ctx } 'Partial'
    Assert-Target ($probe.Rows[0].GroupsWithDisabledOrInactiveMembers.Count -eq 1) 'Readable disabled member retained'
    Assert-Target ($probe.Rows[0].GroupsWithDisabledOrInactiveMembers[0].IsDisabled) 'Disabled state comes from userAccountControl'
    $probe = Invoke-CollectorProbe 'TemplatePermissionsPartial' { Get-AdcsTemplatePermissions -Forest $forest -Server 'selected.example.test' } 'Partial'
    Assert-Target ($probe.Rows.Count -eq 1) 'Readable template ACL retained'
    $null = Invoke-CollectorProbe 'PasswordAgePartial' { Get-AdPrivilegedPasswordAge -DomainContext $ctx } 'Partial'
    $null = Invoke-CollectorProbe 'DnsDenied' { Get-AdDnsZoneInventory -DomainFqdn $state.Child -Server 'dc.child.example.test' } 'Partial'
    $probe = Invoke-CollectorProbe 'DnsTargets' { Get-AdDnsZoneInventory -DomainFqdn $state.Child -Server 'dc.child.example.test' } 'Complete'
    Assert-Target (@($probe.Calls | Where-Object { $_.SearchBase -eq 'CN=MicrosoftDNS,DC=ForestDnsZones,DC=example,DC=test' -and $_.Server -eq 'example.test' }).Count -eq 1) 'Forest DNS uses the forest root naming context and target'
    $null = Invoke-CollectorProbe 'DhcpDenied' { Get-AdDhcpScopeAnalysis -DomainFqdn $state.Child -Server 'dc.child.example.test' } 'Failure'
    $null = Invoke-CollectorProbe 'LegacyCertificateDenied' { Get-AdCertificateServicesInventory -Forest $forest -Server 'selected.example.test' } 'Failure'
    $probe = Invoke-CollectorProbe 'SysvolDenied' { Get-AdSysvolSizeAnalysis -DomainFqdn $state.Child -Server 'dc.child.example.test' } 'Partial'
    Assert-Target ($probe.Rows[0].Status -eq 'Error') 'An unreadable SYSVOL subtree cannot produce a successful size'
    $probe = Invoke-CollectorProbe 'ForestTargets' {
        Get-AdAdReplicationSites -Server 'selected.example.test'
        Get-AdAdReplicationSubnets -Server 'selected.example.test'
        Get-AdAdReplicationSiteLinks -Server 'selected.example.test'
        Get-AdAdForestTrusts -ForestName $forest.Name -Server 'selected.example.test'
        Get-AdSecurityAdcsInventory -Forest $forest -Server 'selected.example.test' -Mode EnterpriseCAs
        Get-AdSecurityCertificateTemplates -Forest $forest -Server 'selected.example.test' -Mode Templates
    } 'Complete'
    Assert-Target (@($probe.Calls | Where-Object { $_.Server -ne 'selected.example.test' }).Count -eq 0) 'Forest collectors honor selected server, including ADCS'

    $state.Mode = 'RequestedDomains'; $state.Calls.Clear(); $failed = $false
    try { $null = Invoke-AdDiscoveryExport -OutputRoot (Join-Path $Root 'RequestedDomains') -Server 'selected.example.test' -Domain @('example.test','typo.example.test') 3>&1 6>&1 } catch {
        $failed = $_.Exception.Message -like '*typo.example.test*'
    }
    Assert-Target $failed 'Every requested domain is validated'
    Assert-Target (@($state.Calls | Where-Object { $_.Command -eq 'Get-ADUser' }).Count -eq 0) 'Invalid domain list stops before data collection'
    Write-Host "PASS: requested domain validation; outputs: $Root"
} $root
