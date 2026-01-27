function Get-AdAdReplicationSubnets {
  [CmdletBinding()]
  param()

  if (-not (Get-Command Get-ADReplicationSubnet -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADReplicationSubnet missing). Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $rows = @()
  try {
    $subnets = Get-ADReplicationSubnet -Filter * -ErrorAction Stop
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
    throw "Failed to enumerate replication subnets. $($_.Exception.Message)"
  }

  return $rows
}
