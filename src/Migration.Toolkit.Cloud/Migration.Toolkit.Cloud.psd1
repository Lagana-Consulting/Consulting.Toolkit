@{
    RootModule            = 'Migration.Toolkit.Cloud.psm1'
    ModuleVersion         = '0.1.0'
    GUID                  = '8a7f6e5d-4c3b-2a1f-0e9d-8c7b6a5f4e3d'
    Author                = 'Lagana Consulting'
    CompanyName           = 'Quest'
    Description           = 'Cloud workload discovery module for Entra ID, Exchange Online, SharePoint, Teams, and M365 Groups using MS-Graph'
    PowerShellVersion     = '5.1'
    RequiredModules       = @(
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Users'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Groups'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.DeviceManagement'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Mail'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Teams'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'Microsoft.Graph.Sites'; ModuleVersion = '2.0.0' }
        @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.0.0' }
    )
    FunctionsToExport     = @(
        # Authentication
        'Connect-AdCloudTenant',
        'Disconnect-AdCloudTenant',
        'Get-AdCloudAuthContext',

        # Entra ID Discovery
        'Get-AdCloudUsers',
        'Get-AdCloudGroups',
        'Get-AdCloudDevices',
        'Get-AdCloudApplications',
        'Get-AdCloudServicePrincipals',
        'Get-AdCloudRoleAssignments',

        # Exchange Online Discovery
        'Get-AdCloudMailboxes',
        'Get-AdCloudDistributionGroups',
        'Get-AdCloudResourceMailboxes',
        'Get-AdCloudMailboxPermissions',

        # SharePoint & OneDrive Discovery
        'Get-AdCloudSharePointSites',
        'Get-AdCloudOneDriveUsage',
        'Get-AdCloudSitePermissions',

        # Teams Discovery
        'Get-AdCloudTeams',
        'Get-AdCloudTeamChannels',
        'Get-AdCloudTeamMembers',

        # M365 Groups
        'Get-AdCloudM365Groups',
        'Get-AdCloudGroupMembers',

        # Orchestration
        'Invoke-AdCloudDiscovery',

        # Utilities
        'Export-AdCloudCsv',
        'New-AdCloudLog',
        'Write-AdCloudLog',
        'Get-AdCloudTenantInfo'
    )
    VariablesToExport     = @()
    AliasesToExport       = @()
    PrivateData           = @{
        PSData = @{
            Tags         = @('ActiveDirectory', 'Entra', 'Microsoft365', 'Exchange', 'SharePoint', 'Teams', 'Migration')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/lagana/Migration.Toolkit'
            ReleaseNotes = 'Initial cloud workload discovery module'
        }
    }
}
