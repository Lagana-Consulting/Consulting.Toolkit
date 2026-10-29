function Get-AdAdFineGrainedPasswordPolicyAssignments {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    [string]$LogPath
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADFineGrainedPasswordPolicy -ErrorAction SilentlyContinue)) {
    Stop-AdDiscoveryCollection -Message 'FGPP cmdlets not available; FGPP assignments were not collected.'
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $pols = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADFineGrainedPasswordPolicy' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
    param($queryServer)
    $queryParams = @{ Filter = '*'; SearchBase = $DomainContext.DomainDn; SearchScope = 'Subtree'; ErrorAction = 'Stop' }
    if ($queryServer) { $queryParams.Server = $queryServer }
    Get-ADFineGrainedPasswordPolicy @queryParams
  })

  $rows = @()
  foreach ($p in $pols) {
    $appliesTo = @($p.AppliesTo)
    if (-not $appliesTo -or $appliesTo.Count -eq 0) { continue }

    foreach ($dn in $appliesTo) {
      if ([string]::IsNullOrWhiteSpace([string]$dn)) { continue }

      $rows += [pscustomobject]@{
        DomainFqdn  = $domain
        PolicyName  = [string]$p.Name
        PolicyDN    = [string]$p.DistinguishedName
        Precedence  = $p.Precedence
        AppliesToDN = [string]$dn
      }
    }
  }

  return @($rows)
}
