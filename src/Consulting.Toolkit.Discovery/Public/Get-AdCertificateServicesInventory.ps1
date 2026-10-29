function Get-AdCertificateServicesInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $Forest,
    [string]$Server
  )

  if (-not (Get-Command Get-ADObject -ErrorAction Stop)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools."
  }

  $results = @()

  try {
    $serverTarget = if ($Server) { $Server } else { [string]$Forest.SchemaMaster }
    $configNc = (Get-ADRootDSE -Server $serverTarget -ErrorAction Stop).configurationNamingContext
    $pkiContainer = "CN=Public Key Services,CN=Services,$configNc"

    # Enumerate Certificate Templates
    $templates = Get-ADObject -SearchBase "CN=Certificate Templates,$pkiContainer" -Filter * -Server $serverTarget -Properties displayName, msPKI-Cert-Template-OID, flags -ErrorAction Stop
    foreach ($template in $templates) {
      $results += [pscustomobject]@{
        ItemType    = 'CertificateTemplate'
        Name        = $template.Name
        DisplayName = $template.displayName
        ObjectDN    = $template.DistinguishedName
        Details     = "OID: $($template.'msPKI-Cert-Template-OID')"
        ForestName  = $Forest.Name
      }
    }

    # Enumerate Enterprise CAs
    $cas = Get-ADObject -SearchBase "CN=Enrollment Services,$pkiContainer" -Filter * -Server $serverTarget -Properties dNSHostName, displayName -ErrorAction Stop
    foreach ($ca in $cas) {
      $results += [pscustomobject]@{
        ItemType    = 'EnterpriseCA'
        Name        = $ca.Name
        DisplayName = $ca.displayName
        ObjectDN    = $ca.DistinguishedName
        Details     = "Host: $($ca.dNSHostName)"
        ForestName  = $Forest.Name
      }
    }

    # Enumerate NTAuth Certificates
    $ntAuthStore = Get-ADObject "CN=NTAuthCertificates,$pkiContainer" -Server $serverTarget -Properties cACertificate -ErrorAction Stop
    $certCount = if ($ntAuthStore.cACertificate) { $ntAuthStore.cACertificate.Count } else { 0 }
    $results += [pscustomobject]@{
      ItemType    = 'NTAuthStore'
      Name        = 'NTAuthCertificates'
      DisplayName = 'Enterprise NTAuth Store'
      ObjectDN    = "CN=NTAuthCertificates,$pkiContainer"
      Details     = "Certificates: $certCount"
      ForestName  = $Forest.Name
    }

  } catch {
    throw
  }

  return $results
}
