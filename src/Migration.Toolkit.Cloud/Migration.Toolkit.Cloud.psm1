Set-StrictMode -Version Latest

$PublicPath = Join-Path $PSScriptRoot 'Public'
$PrivatePath = Join-Path $PSScriptRoot 'Private'

# Dot-source Private first
Get-ChildItem -Path $PrivatePath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Dot-source Public
Get-ChildItem -Path $PublicPath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Export only public functions (defined in psd1)
Export-ModuleMember -Function @(
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
