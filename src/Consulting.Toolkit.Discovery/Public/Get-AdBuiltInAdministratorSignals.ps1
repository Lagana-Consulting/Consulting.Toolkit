function Get-AdBuiltInAdministratorSignals {
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
  $domainSid = (Get-ADDomain -Identity $domain -Server $server -ErrorAction Stop).DomainSID.Value
  $rid500Sid = "$domainSid-500"

  # RID 500 (built-in Administrator)
  $u = Get-ADUser -LDAPFilter "(objectSid=$rid500Sid)" -SearchBase $DomainContext.DomainDn -SearchScope Subtree -Server $server -Properties `
        Enabled,PasswordLastSet,pwdLastSet,lastLogonTimestamp,lastLogonDate,whenChanged,whenCreated,objectGuid,userAccountControl `
        -ErrorAction Stop | Select-Object -First 1

  if (-not $u) { return @() }

  @([pscustomobject]@{
    DomainFqdn         = $domain
    SamAccountName     = [string]$u.SamAccountName
    DistinguishedName  = [string]$u.DistinguishedName
    ObjectGuid         = [string]$u.ObjectGuid
    Enabled            = [bool]$u.Enabled
    UserAccountControl = [int]$u.UserAccountControl
    PasswordLastSet    = $u.PasswordLastSet
    PwdLastSetRaw      = $u.pwdLastSet
    LastLogonDate      = $u.lastLogonDate
    LastLogonTimestamp = $u.lastLogonTimestamp
    WhenCreated        = $u.whenCreated
    WhenChanged        = $u.whenChanged
  })
}
