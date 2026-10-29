function Get-AdDnsZoneInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$DomainFqdn,

    [string]$Server
  )

  if (-not (Get-Command Get-ADObject -ErrorAction Stop)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools."
  }

  $results = @()

  try {
    $ctx = Get-AdAdDomainContext -DomainFqdn $DomainFqdn -Server $Server
    $Server = $ctx.Server
    $domainDn = $ctx.DomainDn
    $forestDn = (Get-ADRootDSE -Server $Server -ErrorAction Stop).rootDomainNamingContext
    $dnsZonesContainers = @(
      @{ Path = "CN=MicrosoftDNS,DC=DomainDnsZones,$domainDn"; Server = $Server; Scope = 'Domain' },
      @{ Path = "CN=MicrosoftDNS,DC=ForestDnsZones,$forestDn"; Server = ($forestDn -replace '^DC=', '' -replace ',DC=', '.'); Scope = 'Forest' }
    )

    foreach ($partition in $dnsZonesContainers) {
      $container = $partition.Path
      $scope = $partition.Scope

      try {
        $zones = @(Get-ADObject -SearchBase $container -Filter "objectClass -eq 'dnsZone'" -Properties name, whenCreated, whenChanged -Server $partition.Server -ErrorAction Stop)

        foreach ($zone in $zones) {
          $results += [pscustomobject]@{
            ZoneName     = $zone.name
            Scope        = $scope
            DomainFqdn   = $DomainFqdn
            DN           = $zone.DistinguishedName
            WhenCreated  = $zone.whenCreated
            WhenChanged  = $zone.whenChanged
            IntegrationType = 'AD-Integrated'
          }
        }
      } catch {
        Write-AdDiscoveryCollectionIssue -Message "Could not enumerate $scope DNS zones for $DomainFqdn." -ErrorRecord $_ -Details @{ SearchBase = $container; Server = $partition.Server }
      }
    }

  } catch {
    throw
  }

  return $results
}
