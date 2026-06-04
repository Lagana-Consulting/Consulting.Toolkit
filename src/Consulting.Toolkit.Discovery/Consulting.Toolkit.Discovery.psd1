@{
    RootModule           = 'Consulting.Toolkit.Discovery.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'dd2682ce-a48e-49a6-887a-25df1f89619f'
    Author               = 'Lagana Consulting'
    CompanyName          = 'Lagana Consulting'
    Copyright            = '(c) 2026 Lagana Consulting'
    Description          = 'Discovery collectors and export pipeline for AD/cloud inventory outputs (contract-first).'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Core')

    # Keep empty in monorepo unless you enforce PSModulePath in build/dev bootstrap
    RequiredModules      = @()

    # Make manifest match the contract surface (psm1 still controls Export-ModuleMember)
    FunctionsToExport    = @(
        'Invoke-AdDiscovery',
        'Invoke-AdDiscoveryExport',
        'Get-AdAdForest',
        'Get-AdAdDomains',
        'Get-AdAdDomainContext',
        'New-AdRunLayout',
        'Export-AdCsvSafe',
        'Export-AdSchemas',
        'Get-AdComputerStatusDetails',
        'Get-AdGroupMembershipDetails',
        'Get-AdSchemaDefinitions',
        'Get-AdUserStatusDetails',
        'New-AdLog',
        'Write-AdLog'
    )

    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    TypesToProcess       = @()
    FormatsToProcess     = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('discovery', 'active-directory', 'inventory', 'assessment')
            ProjectUri = 'https://github.com/laganaconsulting/Consulting.Toolkit'
        }
    }
}
