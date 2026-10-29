function Get-AdAdReplicationSiteLinks {
  [CmdletBinding()]
  param([string]$Server)

  if (-not (Get-Command Get-ADReplicationSiteLink -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADReplicationSiteLink missing). Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $queryParams = @{ Filter = '*'; ErrorAction = 'Stop' }
  if ($Server) { $queryParams.Server = $Server }

  $rows = @()
  try {
    $links = Get-ADReplicationSiteLink @queryParams
    foreach ($l in $links) {
      $rows += [pscustomobject]@{
        Name             = [string]$l.Name
        Cost             = $l.Cost
        ReplicationFrequencyInMinutes = $l.ReplicationFrequencyInMinutes
        SitesIncluded    = ((@($l.SitesIncluded) | Where-Object { $_ }) -join ';')
        DistinguishedName= [string]$l.DistinguishedName
        Description      = [string]$l.Description
      }
    }
  } catch {
    throw
  }

  return $rows
}
