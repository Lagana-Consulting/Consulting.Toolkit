function Get-LcAdOuDelegationAcls {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    $DomainContext,

    [ValidateSet('OneLevel', 'Subtree')]
    [string]$Scope = 'OneLevel'
  )

  if (-not (Get-Command Get-Acl -ErrorAction SilentlyContinue)) {
    throw "Get-Acl not available."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server
  $baseDn = [string]$DomainContext.DomainDn

  # Get OUs
  $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $baseDn -SearchScope $Scope -Server $server -Properties name -ErrorAction Stop

  foreach ($ou in $ous) {
    $dn = [string]$ou.DistinguishedName

    # LDAP path for ACL reads
    $ldapPath = "AD:\$dn"

    $acl = $null
    try {
      $acl = Get-Acl -Path $ldapPath -ErrorAction Stop
    } catch {
      continue
    }

    foreach ($ace in $acl.Access) {
      # Only non-inherited delegations
      if ($ace.IsInherited) { continue }

      [pscustomobject]@{
        DomainFqdn            = $domain
        OuName                = [string]$ou.Name
        OuDistinguishedName   = $dn
        IdentityReference     = [string]$ace.IdentityReference
        ActiveDirectoryRights = [string]$ace.ActiveDirectoryRights
        AccessControlType     = [string]$ace.AccessControlType
        InheritanceType       = [string]$ace.InheritanceType
        ObjectType            = [string]$ace.ObjectType
        InheritedObjectType   = [string]$ace.InheritedObjectType
      }
    }
  }
}
