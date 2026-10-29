function Get-AdAdSpns {
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

  $objs = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADObject' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
      param($queryServer)
      Get-ADObject -LDAPFilter $filter -SearchBase $DomainContext.DomainDn -SearchScope Subtree -Server $queryServer -Properties servicePrincipalName,sAMAccountName -ErrorAction Stop
  })

  foreach ($o in $objs) {
    $spns = @($o.servicePrincipalName)
    if (-not $spns -or $spns.Count -eq 0) { continue }

    $otype = if ($o.ObjectClass -eq 'computer') { 'Computer' } else { 'User' }

    foreach ($spn in $spns) {
      if ([string]::IsNullOrWhiteSpace([string]$spn)) { continue }

      [pscustomobject]@{
        DomainFqdn        = $domain
        ObjectClass       = [string]$o.ObjectClass
        ServicePrincipalName = [string]$spn
        # Compatibility aliases retained for consumers of earlier raw CSVs.
        ObjectType        = $otype
        SamAccountName    = [string]$o.sAMAccountName
        DistinguishedName = [string]$o.DistinguishedName
        SPN               = [string]$spn
      }
    }
  }
}
