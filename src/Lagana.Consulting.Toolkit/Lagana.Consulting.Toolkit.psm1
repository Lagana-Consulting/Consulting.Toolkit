Set-StrictMode -Version Latest

$PublicPath  = Join-Path $PSScriptRoot 'Public'
$PrivatePath = Join-Path $PSScriptRoot 'Private'

# Dot-source Private first
Get-ChildItem -Path $PrivatePath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
  . $_.FullName
}

# Dot-source Public
Get-ChildItem -Path $PublicPath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
  . $_.FullName
}

# Export only public functions
Export-ModuleMember -Function @(
  # Logging / export
  'New-LcLog',
  'Write-LcLog',
  'Export-LcCsv',

  # Tenant safety / auth
  'Confirm-LcTenant',
  'Connect-LcGraph',

  # Run layout + schema
  'New-LcRunLayout',
  'Write-LcSchemaCsv',
  'Get-LcSchemaDefinitions',

  # Forest + domains
  'Get-LcAdForest',
  'Get-LcAdDomains',
  'Get-LcKnownUpnSuffixes',

  'Get-LcAdForestSummary',
  'Get-LcAdForestUpnSuffixes',
  'Get-LcAdReplicationSites',
  'Get-LcAdReplicationSubnets',
  'Get-LcAdReplicationSiteLinks',
  'Get-LcAdForestTrusts',

  'Get-LcAdDomainContext',
  'New-LcDomainRunFolder'


)
