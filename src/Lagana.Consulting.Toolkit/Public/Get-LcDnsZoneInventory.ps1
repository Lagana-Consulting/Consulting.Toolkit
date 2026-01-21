function Get-LcDnsZoneInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$DomainFqdn,

    [string]$Server
  )

  if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools."
  }

  $results = @()

  try {
    $domainDn = (Get-ADDomain -Identity $DomainFqdn -Server $Server -ErrorAction Stop).DistinguishedName
    $dnsZonesContainers = @(
      "CN=MicrosoftDNS,DC=DomainDnsZones,$domainDn",
      "CN=MicrosoftDNS,DC=ForestDnsZones,$domainDn"
    )

    foreach ($container in $dnsZonesContainers) {
      $scope = if ($container -match 'ForestDnsZones') { 'Forest' } else { 'Domain' }

      try {
        $zones = Get-ADObject -SearchBase $container -Filter "objectClass -eq 'dnsZone'" -Properties name, whenCreated, whenChanged -Server $Server -ErrorAction SilentlyContinue

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
        Write-Verbose "Could not enumerate $scope DNS zones: $($_.Exception.Message)"
      }
    }

  } catch {
    Write-Warning "Failed to enumerate DNS zones for $DomainFqdn`: $($_.Exception.Message)"
  }

  return $results
}
