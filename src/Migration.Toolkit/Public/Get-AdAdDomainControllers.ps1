function Get-AdAdDomainControllers {
  <#
  .SYNOPSIS
  Retrieves all domain controllers for a domain.

  .DESCRIPTION
  Enumerates all domain controllers in the specified domain with key properties
  including hostname, site, IP address, operating system, and FSMO role status.
  Returns normalized PSCustomObject array.

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext containing DomainFqdn and Server.
  Required.

  .EXAMPLE
  $ctx = Get-AdAdDomainContext -DomainFqdn "contoso.com"
  $dcs = Get-AdAdDomainControllers -DomainContext $ctx

  Gets all domain controllers in contoso.com domain.

  .EXAMPLE
  $dcs = Get-AdAdDomainControllers -DomainContext $ctx
  $dcs | Where-Object IsGlobalCatalog | Select-Object HostName, Site

  Filters to show only global catalog servers.

  .EXAMPLE
  $pdc = $dcs | Where-Object IsPdc

  Finds the PDC emulator.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  PSCustomObject[]. Array of DC objects with properties:
  - DomainFqdn, HostName, Name, Site, IPv4Address
  - OperatingSystem, IsGlobalCatalog, IsReadOnly, IsPdc, IsEnabled

  .NOTES
  Requires Active Directory PowerShell module.
  DomainContext typically from Get-AdAdDomainContext.

  .LINK
  Get-AdAdDomainContext
  Get-ADDomainController
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

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
