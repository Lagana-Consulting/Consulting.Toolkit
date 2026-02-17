function Get-AdDelegationProtocolTransition {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $baseDn = $DomainContext.DomainDn

    $props = @('userAccountControl', 'msDS-AllowedToDelegateTo', 'distinguishedName', 'samAccountName', 'name', 'objectClass')
    # TRUSTED_TO_AUTH_FOR_DELEGATION = 0x1000000 = 16777216
    $objs = @(Get-ADObject -LDAPFilter '(&(userAccountControl:1.2.840.113556.1.4.803:=16777216)(msDS-AllowedToDelegateTo=*))' `
            -SearchBase $baseDn -Server $server -Properties $props -ErrorAction Stop)

    foreach ($o in $objs) {
        $targets = @($o.'msDS-AllowedToDelegateTo')
        [pscustomobject]@{
            DomainFqdn          = $domain
            Name                = $o.Name
            SamAccountName      = $o.SamAccountName
            ObjectClass         = $o.ObjectClass
            DistinguishedName   = $o.DistinguishedName
            TrustedToAuthForDelegation = $true
            AllowedToDelegateTo = ($targets -join ';')
            TargetCount         = $targets.Count
        }
    }
}
