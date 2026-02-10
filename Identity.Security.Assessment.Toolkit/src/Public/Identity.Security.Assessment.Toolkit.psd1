@{
    RootModule           = 'Identity.Security.Assessment.Toolkit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'f2c0b84e-2d6a-4a34-8f45-0ff2c6b6c8b1'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    Description          = 'Identity Security Assessment Toolkit (AD, Entra ID, M365)'
    Author               = 'Lagana Consulting'
    CompanyName          = 'Lagana Consulting'
    FunctionsToExport    = @(
        'Invoke-IdentitySecurityAssessment',
        'Get-SATOutputRoot',
        'Set-SATOutputRoot',
        'Invoke-SATDiscovery',
        'Invoke-SATADSnapshot',
        'Invoke-SATAzureHoundAnalysis',
        'Invoke-SATBloodHoundAnalysis',
        'Invoke-SATSharpHoundCollection',
        'Invoke-SATNucleiScan',
        'Invoke-SATNucleiAnalysis',
        'Invoke-SATNetworkVulnAssessment',
        'Invoke-SATWebScan',
        'Invoke-SATPackageEvidence',
        'Get-AdSecurityFindings',
        'Export-SATFindings'
    )
    PrivateData          = @{
        PSData = @{
            Tags         = @('PowerShell', 'Security', 'Assessment', 'ActiveDirectory', 'EntraID', 'M365')
            ProjectUri   = ''
            LicenseUri   = ''
            ReleaseNotes = ''
        }
    }
}
