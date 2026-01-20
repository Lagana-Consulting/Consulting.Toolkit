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
    'New-LcLog',
    'Write-LcLog',
    'Export-LcCsv',
    'Confirm-LcTenant',
    'Connect-LcGraph'
  )

  CmdletsToExport   = @()
  VariablesToExport = @()
  AliasesToExport   = @()

  PrivateData = @{
    PSData = @{
      Tags = @('PowerShell','Toolkit','Consulting')
      ProjectUri = ''
      LicenseUri = ''
      ReleaseNotes = 'Initial scaffold.'
    }
  }
}
