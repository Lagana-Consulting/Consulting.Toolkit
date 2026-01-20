function Get-LcAdReplicationSiteLinks {
  [CmdletBinding()]
  param()

  if (-not (Get-Command Get-ADReplicationSiteLink -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADReplicationSiteLink missing). Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $rows = @()
  try {
    $links = Get-ADReplicationSiteLink -Filter * -ErrorAction Stop
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
    throw "Failed to enumerate site links. $($_.Exception.Message)"
  }

  return $rows
}
