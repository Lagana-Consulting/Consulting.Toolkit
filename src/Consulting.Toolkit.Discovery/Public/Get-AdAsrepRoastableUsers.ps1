function Get-AdAsrepRoastableUsers {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext
  )

  if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADUser missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = if ($DomainContext.Server) { [string]$DomainContext.Server } else { [string]$DomainContext.DomainController }

  # UF_DONT_REQUIRE_PREAUTH = 0x00400000 (4194304)
  $flag = 4194304

  $users = @(Get-ADUser -Filter * -SearchBase $DomainContext.DomainDn -SearchScope Subtree -Server $server -Properties userAccountControl,Enabled,PasswordLastSet,objectGuid -ErrorAction Stop |
    Where-Object { (($_.userAccountControl -band $flag) -ne 0) })

  foreach ($u in $users) {
    [pscustomobject]@{
      DomainFqdn         = $domain
      SamAccountName     = [string]$u.SamAccountName
      DistinguishedName  = [string]$u.DistinguishedName
      ObjectGuid         = [string]$u.ObjectGuid
      Enabled            = [bool]$u.Enabled
      UserAccountControl = [int]$u.userAccountControl
      PasswordLastSet    = $u.PasswordLastSet
      IsAsrepRoastable   = $true
    }
  }
}
