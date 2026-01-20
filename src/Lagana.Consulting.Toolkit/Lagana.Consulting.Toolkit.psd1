@{
  RootModule        = 'Lagana.Consulting.Toolkit.psm1'
  ModuleVersion     = '0.1.0'
  GUID              = '8593c972-06bc-4b0a-a680-0a61fcda0c3e'
  Author            = 'Lagana Consulting'
  CompanyName       = 'Lagana Consulting'
  Copyright         = '(c) Lagana Consulting. All rights reserved.'
  Description       = 'Reusable PowerShell toolkit for consulting automation.'
  PowerShellVersion = '5.1'

    FunctionsToExport = @(
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

  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData = @{
    PSData = @{
      Tags = @('PowerShell','Toolkit','Consulting','ActiveDirectory','MicrosoftGraph')
      ProjectUri = ''
      LicenseUri = ''
      ReleaseNotes = 'Initial scaffold with helpers, run layout, schema, and forest/domain enumeration.'
    }
  }
}