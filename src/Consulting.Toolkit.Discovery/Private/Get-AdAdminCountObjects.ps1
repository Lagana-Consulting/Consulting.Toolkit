function Get-AdAdminCountObjects {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADObject missing)."
    }

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $objs = @()
    try {
        $objs = @(Get-ADObject -LDAPFilter '(adminCount=1)' -SearchBase $baseDn -Server $server `
                -Properties objectClass, adminCount, distinguishedName, name -ErrorAction Stop)
    } catch {
        $objs = @()
    }

    foreach ($o in $objs) {
        [pscustomobject]@{
            DomainFqdn        = $domain
            Name              = $o.Name
            ObjectClass       = $o.ObjectClass
            DistinguishedName = $o.DistinguishedName
            AdminCount        = $o.adminCount
        }
    }
}
