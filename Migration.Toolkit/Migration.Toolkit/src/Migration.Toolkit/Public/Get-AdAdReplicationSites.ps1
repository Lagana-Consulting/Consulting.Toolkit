function Get-AdAdReplicationSites {
  [CmdletBinding()]
  param(
    [string]$Server
  )

  if (-not (Get-Command Get-ADReplicationSite -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADReplicationSite missing). Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $rows = @()
  try {
    $sites = Get-ADReplicationSite -Filter * -ErrorAction Stop
    foreach ($s in $sites) {
      $rows += [pscustomobject]@{
        Name        = [string]$s.Name
        DistinguishedName = [string]$s.DistinguishedName
        Description = [string]$s.Description
      }
    }
  } catch {
    throw "Failed to enumerate replication sites. $($_.Exception.Message)"
  }

  return $rows
}
