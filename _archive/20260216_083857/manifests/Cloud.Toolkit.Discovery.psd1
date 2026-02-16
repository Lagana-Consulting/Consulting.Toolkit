@{
    RootModule        = 'Cloud.Toolkit.Discovery.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '8a7f6e5d-4c3b-2a1f-0e9d-8c7b6a5f4e3d'
    Author            = 'Lagana Consulting'
    CompanyName       = 'Quest'
    Description       = 'Cloud workload discovery module for Entra ID, Exchange Online, SharePoint, Teams, and M365 Groups using MS-Graph'
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    FunctionsToExport = @(
        # Authentication
        'Connect-AzCloudTenant',
        'Disconnect-AzCloudTenant',
        'Get-AzCloudAuthContext',

        # Entra ID Discovery
        'Get-AzCloudUsers',
        'Get-AzCloudGroups',
        'Get-AzCloudDevices',
        'Get-AzCloudApplications',
        'Get-AzCloudServicePrincipals',
        'Get-AzCloudRoleAssignments',

        # Exchange Online Discovery
        'Get-AzCloudMailboxes',
        'Get-AzCloudDistributionGroups',
        'Get-AzCloudResourceMailboxes',
        'Get-AzCloudMailboxPermissions',

        # SharePoint & OneDrive Discovery
        'Get-AzCloudSharePointSites',
        'Get-AzCloudOneDriveUsage',
        'Get-AzCloudSitePermissions',

        # Teams Discovery
        'Get-AzCloudTeams',
        'Get-AzCloudTeamChannels',
        'Get-AzCloudTeamMembers',

        # M365 Groups
        'Get-AzCloudM365Groups',
        'Get-AzCloudGroupMembers',

        # Data Governance & Security
        'Get-AzCloudSensitivityLabels',

        # Orchestration
        'Invoke-AzCloudDiscovery',

        # Utilities
        'Export-AzCloudCsv',
        'New-AzCloudLog',
        'Write-AzCloudLog',
        'Get-AzCloudTenantInfo'
    )
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('ActiveDirectory', 'Entra', 'Microsoft365', 'Exchange', 'SharePoint', 'Teams', 'Migration')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/lagana/Migration.Toolkit'
            ReleaseNotes = 'Initial cloud workload discovery module'
        }
    }
}
