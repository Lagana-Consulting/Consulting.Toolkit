function Get-AdAdReplicationSites {
  [CmdletBinding()]
  param(
    [string]$Server
  )

  if (-not (Get-Command Get-ADReplicationSite -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADReplicationSite missing). Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $queryParams = @{ Filter = '*'; ErrorAction = 'Stop' }
  if ($Server) { $queryParams.Server = $Server }

  $rows = @()
  try {
    $sites = Get-ADReplicationSite @queryParams
    foreach ($s in $sites) {
      $rows += [pscustomobject]@{
        Name        = [string]$s.Name
        DistinguishedName = [string]$s.DistinguishedName
        Description = [string]$s.Description
      }
    }
  } catch {
    throw
  }

  return $rows
}
