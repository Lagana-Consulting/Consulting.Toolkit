@{
  # Script module file associated with this manifest
  RootModule           = 'Identity.Security.Assessment.Toolkit.psm1'

  # Version number of this module.
  ModuleVersion        = '0.1.0'

  # Supported PSEditions
  CompatiblePSEditions = @('Core')

  # ID used to uniquely identify this module
  GUID                 = 'a556b831-7f00-4a9c-b254-46fb2115afd8'

  # Author of this module
  Author               = 'Lagana Consulting'
  CompanyName          = 'Lagana Consulting'
  Copyright            = '(c) 2026 Lagana Consulting'

  # Description of the functionality provided by this module
  Description          = 'Identity security assessment tooling (collect, analyze, and report identity/security findings).'

  # Minimum version of the PowerShell engine required by this module
  PowerShellVersion    = '7.2'

  # Modules that must be imported into the global environment prior to importing this module
  # NOTE: Leave empty for monorepo dev to avoid PSModulePath resolution issues.
  RequiredModules      = @()

  # Functions to export from this module
  FunctionsToExport    = @('*')

  CmdletsToExport      = @()
  VariablesToExport    = @()
  AliasesToExport      = @()

  # Private data to pass to the module specified in RootModule/ModuleToProcess
  PrivateData          = @{
    PSData = @{
      Tags       = @('security', 'identity', 'assessment')
      ProjectUri = 'https://github.com/laganaconsulting/Consulting.Toolkit'
    }
  }
}
