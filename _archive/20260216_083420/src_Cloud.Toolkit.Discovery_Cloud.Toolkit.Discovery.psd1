@
@{
  AliasesToExport = @(
  )
  RootModule = 'Cloud.Toolkit.Cloud.psm1'
  GUID = '8a7f6e5d-4c3b-2a1f-0e9d-8c7b6a5f4e3d'
  ModuleVersion = '0.1.0'
  Author = 'Lagana Consulting'
  FunctionsToExport = @(
    'Connect-AzCloudTenant'
    'Disconnect-AzCloudTenant'
    'Get-AzCloudAuthContext'
    'Get-AzCloudUsers'
    'Get-AzCloudGroups'
    'Get-AzCloudDevices'
    'Get-AzCloudApplications'
    'Get-AzCloudServicePrincipals'
    'Get-AzCloudRoleAssignments'
    'Get-AzCloudMailboxes'
    'Get-AzCloudDistributionGroups'
    'Get-AzCloudResourceMailboxes'
    'Get-AzCloudMailboxPermissions'
    'Get-AzCloudSharePointSites'
    'Get-AzCloudOneDriveUsage'
    'Get-AzCloudSitePermissions'
    'Get-AzCloudTeams'
    'Get-AzCloudTeamChannels'
    'Get-AzCloudTeamMembers'
    'Get-AzCloudM365Groups'
    'Get-AzCloudGroupMembers'
    'Get-AzCloudSensitivityLabels'
    'Invoke-AzCloudDiscovery'
    'Export-AzCloudCsv'
    'New-AzCloudLog'
    'Write-AzCloudLog'
    'Get-AzCloudTenantInfo'
  )
  PowerShellVersion = '5.1'
  CompanyName = 'Quest'
  VariablesToExport = @(
  )
  Description = 'Cloud workload discovery module for Entra ID, Exchange Online, SharePoint, Teams, and M365 Groups using MS-Graph'
  PrivateData = 
Name                           Value
----                           -----
PSData                         {[ProjectUri, https://github.com/lagana/Migration.Toolkit], [Tags, System.Object[]], [ReleaseNotes, Initial cloud workload discovery module], [LicenseUri, https://opensource.org/lic…
  RequiredModules = @(
  )
}

