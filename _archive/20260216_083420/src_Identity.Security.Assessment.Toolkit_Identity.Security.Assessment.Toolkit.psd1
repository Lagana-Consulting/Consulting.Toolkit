@
@{
  FunctionsToExport = @(
    'Invoke-IdentitySecurityAssessment'
    'Get-SATOutputRoot'
    'Set-SATOutputRoot'
    'Invoke-SATDiscovery'
    'Invoke-SATADSnapshot'
    'Invoke-SATBloodHoundAnalysis'
    'Invoke-SATSharpHoundCollection'
    'Invoke-SATNucleiScan'
    'Invoke-SATNucleiAnalysis'
    'Invoke-SATNetworkVulnAssessment'
    'Invoke-SATWebScan'
    'Invoke-SATPackageEvidence'
    'Get-AdSecurityFindings'
    'Export-SATFindings'
  )
  CompatiblePSEditions = @(
    'Desktop'
    'Core'
  )
  RootModule = 'Identity.Security.Assessment.Toolkit.psm1'
  CompanyName = 'Lagana Consulting'
  PowerShellVersion = '5.1'
  ModuleVersion = '0.1.0'
  Description = 'Identity Security Assessment Toolkit (AD, Entra ID, M365)'
  PrivateData = 
Name                           Value
----                           -----
PSData                         {[ProjectUri, ], [Tags, System.Object[]], [ReleaseNotes, ], [LicenseUri, ]}
  RequiredModules = @(
    'Migration.Toolkit.Analysis'
  )
  Author = 'Lagana Consulting'
  GUID = 'f2c0b84e-2d6a-4a34-8f45-0ff2c6b6c8b1'
}

