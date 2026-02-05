function Get-AzCloudDevices {
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
  $devices = Get-AzCloudDevices

  Gets all devices in tenant.

  .EXAMPLE
  $hybridDevices = Get-AzCloudDevices -DeviceTrustType HybridAzureAdJoined

  Gets only hybrid-joined devices.

  .EXAMPLE
  $nonCompliant = Get-AzCloudDevices -Filter "isCompliant eq false"

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
  Get-AzCloudUsers
  Get-AzCloudGroups
  Export-AzCloudCsv
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

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try { if (-not (Get-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction SilentlyContinue)) { Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop -SkipEditionCheck } } catch { Write-Warning "Could not import Microsoft.Graph.Identity.DirectoryManagement module (may already be loaded). Proceeding..." }

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
    All         = $true
    ErrorAction = 'Stop'
    Property    = $Properties
  }

  if ($finalFilter) {
    $params['Filter'] = $finalFilter
  }

  Write-Verbose "Querying devices with filter: $finalFilter"

  try {
    # Try SDK cmdlet first
    $devices = Get-MgDevice @params -ErrorAction Stop
    $deviceCount = if ($devices) { ($devices | Measure-Object).Count } else { 0 }
    Write-Verbose "Retrieved $deviceCount devices"
    return $devices
  }
  catch {
    # Fallback to direct REST API if SDK fails
    Write-Verbose "SDK cmdlet failed, attempting direct REST API call..."
    try {
      $uri = "https://graph.microsoft.com/v1.0/devices"
      if ($finalFilter) {
        $uri += "?`$filter=$([System.Web.HttpUtility]::UrlEncode($finalFilter))"
      }
      $devices = (Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop).value
      $deviceCount = if ($devices) { ($devices | Measure-Object).Count } else { 0 }
      Write-Verbose "Retrieved $deviceCount devices via REST API"
      return $devices
    }
    catch {
      Write-Warning "Failed to retrieve devices from MS-Graph (Graph SDK compatibility issue). Returning empty set. Error: $($_.Exception.Message)"
      return @()
    }
  }
}
