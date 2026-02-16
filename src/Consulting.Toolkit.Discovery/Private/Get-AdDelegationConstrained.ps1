function Get-AdDelegationConstrained {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $props = @('msDS-AllowedToDelegateTo', 'distinguishedName', 'samAccountName', 'name', 'objectClass')
    $objs = @(Get-ADObject -LDAPFilter '(msDS-AllowedToDelegateTo=*)' `
            -SearchBase $baseDn -Server $server -Properties $props -ErrorAction SilentlyContinue)

    foreach ($o in $objs) {
        $targets = @($o.'msDS-AllowedToDelegateTo')
        [pscustomobject]@{
            DomainFqdn          = $domain
            Name                = $o.Name
            SamAccountName      = $o.SamAccountName
            ObjectClass         = $o.ObjectClass
            DistinguishedName   = $o.DistinguishedName
            AllowedToDelegateTo = ($targets -join ';')
            TargetCount         = $targets.Count
        }
    }
}
