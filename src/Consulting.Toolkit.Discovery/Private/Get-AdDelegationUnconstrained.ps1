function Get-AdDelegationUnconstrained {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $props = @('userAccountControl', 'distinguishedName', 'samAccountName', 'name', 'objectClass', 'servicePrincipalName')
    $objs = @(Get-ADObject -LDAPFilter '(&(userAccountControl:1.2.840.113556.1.4.803:=524288))' `
            -SearchBase $baseDn -Server $server -Properties $props -ErrorAction SilentlyContinue)

    foreach ($o in $objs) {
        [pscustomobject]@{
            DomainFqdn        = $domain
            Name              = $o.Name
            SamAccountName    = $o.SamAccountName
            ObjectClass       = $o.ObjectClass
            DistinguishedName = $o.DistinguishedName
            SPNCount          = @($o.servicePrincipalName).Count
        }
    }
}
