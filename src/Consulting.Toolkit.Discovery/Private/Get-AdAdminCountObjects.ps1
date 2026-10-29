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
                -Properties objectClass, adminCount, distinguishedName, name, samAccountName -ErrorAction Stop)
    } catch {
        throw
    }

    foreach ($o in $objs) {
        [pscustomobject]@{
            DomainFqdn        = $domain
            ObjectClass       = $o.ObjectClass
            SamAccountName    = $o.SamAccountName
            DistinguishedName = $o.DistinguishedName
            AdminCount        = $o.adminCount
            IsProtectedByAdminSDHolder = $null
        }
    }
}
