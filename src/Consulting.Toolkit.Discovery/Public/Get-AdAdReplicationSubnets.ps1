function Get-AdAdReplicationSubnets {
  [CmdletBinding()]
  param([string]$Server)

  if (-not (Get-Command Get-ADReplicationSubnet -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADReplicationSubnet missing). Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $queryParams = @{ Filter = '*'; ErrorAction = 'Stop' }
  if ($Server) { $queryParams.Server = $Server }

  $rows = @()
  try {
    $subnets = Get-ADReplicationSubnet @queryParams
    foreach ($sn in $subnets) {
      $rows += [pscustomobject]@{
        Name             = [string]$sn.Name
        Site             = [string]$sn.Site
        Location         = [string]$sn.Location
        DistinguishedName= [string]$sn.DistinguishedName
        Description      = [string]$sn.Description
      }
    }
  } catch {
    throw
  }

  return $rows
}
