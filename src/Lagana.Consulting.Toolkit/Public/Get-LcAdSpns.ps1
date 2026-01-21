function Get-LcAdSpns {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADObject missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  # Objects that can have SPNs: user and computer
  $filter = "(|(objectClass=user)(objectClass=computer))"

  $objs = @()
  try {
    $objs = @(Get-ADObject -LDAPFilter $filter -Server $server -Properties servicePrincipalName,sAMAccountName -ErrorAction Stop)
  } catch {
    throw "Failed to enumerate SPN-bearing objects for $domain via $server. $($_.Exception.Message)"
  }

  foreach ($o in $objs) {
    $spns = @($o.servicePrincipalName)
    if (-not $spns -or $spns.Count -eq 0) { continue }

    $otype = if ($o.ObjectClass -eq 'computer') { 'Computer' } else { 'User' }

    foreach ($spn in $spns) {
      if ([string]::IsNullOrWhiteSpace([string]$spn)) { continue }

      [pscustomobject]@{
        DomainFqdn        = $domain
        ObjectType        = $otype
        SamAccountName    = [string]$o.sAMAccountName
        DistinguishedName = [string]$o.DistinguishedName
        SPN              = [string]$spn
      }
    }
  }
}
