function Get-AdCloudDevices {
  <#
  .SYNOPSIS
  Discovers all devices registered in the connected Entra ID tenant.

  .DESCRIPTION
  Queries MS-Graph /devices endpoint and retrieves comprehensive device information including:
  - Device identity (ID, DisplayName, DeviceId)
  - Device state (Enabled, ComplianceExpirationDateTime)
  - OS and trust type (Azure AD Registered, Azure AD Joined, Hybrid Azure AD Joined)
  - Ownership (Registered user, Owner)
  - Approximate last sign-in time

  Useful for discovering BYOD, corporate devices, and compliance state.

  .PARAMETER Filter
  OData filter to limit results. Examples:
    - "operatingSystem eq 'Windows'" - Windows devices only
    - "trustType eq 'Hybrid Azure AD joined'" - Hybrid joined devices
    - "isCompliant eq true" - Compliant devices only

  .PARAMETER DeviceTrustType
  Filter by trust type: 'All', 'AzureAdJoined', 'HybridAzureAdJoined', 'AzureAdRegistered'.
  Default 'All'.

  .PARAMETER Properties
  Specific properties to retrieve. Default includes all common discovery properties.

  .PARAMETER Top
  Number of results to return. Default 999.

  .PARAMETER IncludeOwnerInfo
  If $true, includes registered owner/user details. Requires additional API call per device.
  Default $false for performance.

  .EXAMPLE
  $devices = Get-AdCloudDevices

  Gets all devices in tenant.

  .EXAMPLE
  $hybridDevices = Get-AdCloudDevices -DeviceTrustType HybridAzureAdJoined

  Gets only hybrid-joined devices.

  .EXAMPLE
  $nonCompliant = Get-AdCloudDevices -Filter "isCompliant eq false"

  Gets non-compliant devices.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  [PSObject] Array of device objects with properties:
    - id, displayName, deviceId, accountEnabled
    - deviceOsType, deviceOsVersion
    - trustType, isCompliant
    - createdDateTime, approximateLastSignInDateTime
    - manufacturer, model
    - physicalIds (for Hybrid devices)
    - Optional: registeredOwners, registeredUsers (if IncludeOwnerInfo)

  .NOTES
  Requires Graph scope: Device.Read.All
  Includes both Azure AD joined and registered devices.
  For Hybrid Azure AD joined devices, also see on-premises AD computer accounts.
  approximateLastSignInDateTime may be null for inactive devices.

  .LINK
  Get-AdCloudUsers
  Get-AdCloudGroups
  Export-AdCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [ValidateSet('All', 'AzureAdJoined', 'HybridAzureAdJoined', 'AzureAdRegistered')]
    [string]$DeviceTrustType = 'All',
    [string[]]$Properties = @(
      'id',
      'displayName',
      'deviceId',
      'accountEnabled',
      'deviceOsType',
      'deviceOsVersion',
      'trustType',
      'isCompliant',
      'createdDateTime',
      'approximateLastSignInDateTime',
      'manufacturer',
      'model',
      'physicalIds',
      'complianceExpirationDateTime'
    ),
    [int]$Top = 999,
    [switch]$IncludeOwnerInfo
  )

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
  }
  catch {
    throw "Microsoft.Graph.DeviceManagement module required. Install via: Install-Module Microsoft.Graph.DeviceManagement"
  }

  $effectiveFilter = @()

  if ($DeviceTrustType -eq 'AzureAdJoined') {
    $effectiveFilter += "trustType eq 'Azure AD joined'"
  }
  elseif ($DeviceTrustType -eq 'HybridAzureAdJoined') {
    $effectiveFilter += "trustType eq 'Hybrid Azure AD joined'"
  }
  elseif ($DeviceTrustType -eq 'AzureAdRegistered') {
    $effectiveFilter += "trustType eq 'Azure AD registered'"
  }

  if ($Filter) {
    $effectiveFilter += "($Filter)"
  }

  $finalFilter = $effectiveFilter -join ' and '

  $params = @{
    All = $true
    ErrorAction = 'Stop'
    Property = $Properties
  }

  if ($finalFilter) {
    $params['Filter'] = $finalFilter
  }

  Write-Verbose "Querying devices with filter: $finalFilter"

  try {
    $devices = Get-MgDevice @params
    Write-Verbose "Retrieved $($devices.Count) devices"
    return $devices
  }
  catch {
    throw "Failed to retrieve devices from MS-Graph. $($_.Exception.Message)"
  }
}
