function Get-AdUsersSidHistory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADUser missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $users = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADUser SID history' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
    param($queryServer)
    Get-ADUser -LDAPFilter '(sIDHistory=*)' -SearchBase $DomainContext.DomainDn -SearchScope Subtree -Server $queryServer -Properties SIDHistory -ErrorAction Stop
  })

  foreach ($u in $users) {
    $hist = @($u.SIDHistory)
    if (-not $hist -or $hist.Count -eq 0) { continue }

    foreach ($sid in $hist) {
      [pscustomobject]@{
        DomainFqdn        = $domain
        SamAccountName    = [string]$u.SamAccountName
        DistinguishedName = [string]$u.DistinguishedName
        SidHistory        = [string]$sid
      }
    }
  }
}
