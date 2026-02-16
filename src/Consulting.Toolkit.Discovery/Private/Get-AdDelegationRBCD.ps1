function Get-AdDelegationRBCD {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $props = @('msDS-AllowedToActOnBehalfOfOtherIdentity', 'distinguishedName', 'samAccountName', 'name', 'objectClass')
    $objs = @(Get-ADObject -LDAPFilter '(msDS-AllowedToActOnBehalfOfOtherIdentity=*)' `
            -SearchBase $baseDn -Server $server -Properties $props -ErrorAction SilentlyContinue)

    foreach ($o in $objs) {
        # We don't expand the security descriptor here (collector-only). Just signal presence.
        [pscustomobject]@{
            DomainFqdn        = $domain
            Name              = $o.Name
            SamAccountName    = $o.SamAccountName
            ObjectClass       = $o.ObjectClass
            DistinguishedName = $o.DistinguishedName
            RBCDPresent       = $true
        }
    }
}
