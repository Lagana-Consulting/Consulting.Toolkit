function Get-AdSpnAccounts {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $props = @('servicePrincipalName', 'distinguishedName', 'samAccountName', 'name', 'objectClass', 'userAccountControl')
    $objs = @(Get-ADObject -LDAPFilter '(servicePrincipalName=*)' -SearchBase $baseDn -Server $server `
            -Properties $props -ErrorAction SilentlyContinue)

    foreach ($o in $objs) {
        $spns = @($o.servicePrincipalName)
        [pscustomobject]@{
            DomainFqdn        = $domain
            Name              = $o.Name
            SamAccountName    = $o.SamAccountName
            ObjectClass       = $o.ObjectClass
            DistinguishedName = $o.DistinguishedName
            SPNCount          = $spns.Count
            SPNs              = ($spns -join ';')
        }
    }
}
