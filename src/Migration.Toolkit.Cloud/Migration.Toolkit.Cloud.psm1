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
