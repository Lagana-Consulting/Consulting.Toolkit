function Get-AdSpnAccounts {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $props = @('servicePrincipalName', 'distinguishedName', 'samAccountName', 'name', 'objectClass', 'userAccountControl', 'pwdLastSet')
    $objs = @(Get-ADObject -LDAPFilter '(servicePrincipalName=*)' -SearchBase $baseDn -Server $server `
            -Properties $props -ErrorAction Stop)

    foreach ($o in $objs) {
        $spns = @($o.servicePrincipalName)
        [pscustomobject]@{
            DomainFqdn        = $domain
            Name              = $o.Name
            SamAccountName    = $o.SamAccountName
            ObjectClass       = $o.ObjectClass
            DistinguishedName = $o.DistinguishedName
            Enabled           = if ($o.PSObject.Properties['userAccountControl'] -and $null -ne $o.userAccountControl) { ($o.userAccountControl -band 2) -eq 0 } else { $null }
            PasswordLastSetUtc = if ($o.PSObject.Properties['pwdLastSet']) { $date = ConvertFrom-AdFileTime -FileTime $o.pwdLastSet; if ($date) { $date.ToString('o') } else { $null } } else { $null }
            SPNCount          = $spns.Count
            SPNs              = ($spns -join ';')
        }
    }
}
