function Get-LcCertificateServicesInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $Forest
  )

  if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools."
  }

  $results = @()

  try {
    $configNc = $Forest.PartitionsContainer -replace '^CN=Partitions,', ''
    $pkiContainer = "CN=Public Key Services,CN=Services,$configNc"

    # Enumerate Certificate Templates
    $templates = Get-ADObject -SearchBase "CN=Certificate Templates,$pkiContainer" -Filter * -Properties displayName, msPKI-Cert-Template-OID, flags -ErrorAction SilentlyContinue
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
    $cas = Get-ADObject -SearchBase "CN=Enrollment Services,$pkiContainer" -Filter * -Properties dNSHostName, displayName -ErrorAction SilentlyContinue
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
    $ntAuthStore = Get-ADObject "CN=NTAuthCertificates,$pkiContainer" -Properties cACertificate -ErrorAction SilentlyContinue
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
    Write-Warning "Failed to enumerate Certificate Services: $($_.Exception.Message)"
  }

  return $results
}
