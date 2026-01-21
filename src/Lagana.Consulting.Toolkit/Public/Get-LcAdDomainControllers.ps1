function Get-LcAdDomainControllers {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    $DomainContext
  )

  if (-not (Get-Command Get-ADDomainController -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $dcs = @()
  try {
    $dcs = @(Get-ADDomainController -Filter * -Server $domain -ErrorAction Stop |
      Sort-Object HostName)
  } catch {
    throw "Failed to enumerate domain controllers for $domain. $($_.Exception.Message)"
  }

  foreach ($dc in $dcs) {
    [pscustomobject]@{
      DomainFqdn      = $domain
      HostName        = [string]$dc.HostName
      Name            = [string]$dc.Name
      Site            = [string]$dc.Site
      IPv4Address     = [string]$dc.IPv4Address
      OperatingSystem = [string]$dc.OperatingSystem
      IsGlobalCatalog = [bool]$dc.IsGlobalCatalog
      IsReadOnly      = [bool]$dc.IsReadOnly
      IsPdc           = [bool]$dc.IsPdc
      IsEnabled       = [bool]$dc.IsEnabled
    }
  }
}
