function Get-AdDelegationRBCD {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $props = @('msDS-AllowedToActOnBehalfOfOtherIdentity', 'distinguishedName', 'samAccountName', 'name', 'objectClass')
    $objs = @(Get-ADObject -LDAPFilter '(msDS-AllowedToActOnBehalfOfOtherIdentity=*)' `
            -SearchBase $baseDn -Server $server -Properties $props -ErrorAction Stop)

    foreach ($o in $objs) {
        # Collector-only: we do not fully expand RBCD ACEs here.
        [pscustomobject]@{
            DomainFqdn        = $domain
            TargetName        = $o.Name
            TargetDn          = $o.DistinguishedName
            AllowedPrincipal  = $null
            AllowedPrincipalSid = $null
            AccessType        = $null
        }
    }
}
