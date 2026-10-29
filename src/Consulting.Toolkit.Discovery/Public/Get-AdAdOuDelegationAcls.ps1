function Get-AdAdOuDelegationAcls {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    [ValidateSet('OneLevel','Subtree')]
    [string]$Scope = 'OneLevel'
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADObject missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server
  $baseDn = [string]$DomainContext.DomainDn

  # Get OUs
  $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $baseDn -SearchScope $Scope -Server $server -Properties name -ErrorAction Stop

  foreach ($ou in $ous) {
    $dn = [string]$ou.DistinguishedName

    $acl = $null
    try {
      # Read through the selected DC, rather than the runner's default AD: drive.
      $acl = (Get-ADObject -Identity $dn -Server $server -Properties nTSecurityDescriptor -ErrorAction Stop).nTSecurityDescriptor
      if (-not $acl) { throw "No security descriptor was returned for '$dn'." }
    } catch {
      Write-AdDiscoveryCollectionIssue -Message "OU ACL could not be read: $dn. $($_.Exception.Message)" -ErrorRecord $_
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
