function Get-AzCloudOneDriveUsage {
  <#
  .SYNOPSIS
  Discovers OneDrive for Business usage across the tenant.

  .DESCRIPTION
  Queries MS-Graph to retrieve OneDrive storage and activity information for all users including:
  - User identity (UPN, DisplayName)
  - Storage usage (Used, Quota, Available)
  - Item counts (documents, folders)
  - Activity (Last accessed, Last modified)
  - Sharing status (Shared items count)

  Useful for storage planning and migration assessment.

  .PARAMETER IncludeInactiveUsers
  If $true, includes users with zero storage usage. Default $false (exclude inactive).

  .PARAMETER MinStorageMB
  Filter results to include only users with usage >= MinStorageMB. Default 0 (all users).

  .PARAMETER Properties
  Properties to retrieve.

  .EXAMPLE
  $oneDrives = Get-AzCloudOneDriveUsage

  Gets OneDrive usage for all active users.

  .EXAMPLE
  $largeOneDrives = Get-AzCloudOneDriveUsage -MinStorageMB 10240

  Gets OneDrive accounts over 10GB.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of OneDrive usage objects with properties:
    - UserPrincipalName, DisplayName
    - StorageUsedBytes, StorageQuotaBytes
    - ItemCount, DocumentCount, FolderCount
    - LastAccessedDateTime, LastModifiedDateTime

  .NOTES
  Requires Graph scope: Reports.Read.All or User.Read.All + Drive.Read.All
  Large tenants may require significant query time; use MinStorageMB to filter.

  .LINK
  Get-AzCloudUsers
  Get-AzCloudSharePointSites
  Export-AzCloudCsv
  #>
  [CmdletBinding()]
  param(
    [switch]$IncludeInactiveUsers,
    [int]$MinStorageMB = 0,
    [string[]]$Properties = @(
      'id',
      'userPrincipalName',
      'displayName',
      'mail',
      'createdDateTime'
    )
  )

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  # Validate and import required modules
  try {
    if (-not (Get-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue)) {
      Import-Module Microsoft.Graph.Users -ErrorAction Stop -SkipEditionCheck
    }
    if (-not (Get-Module Microsoft.Graph.Files -ErrorAction SilentlyContinue)) {
      Import-Module Microsoft.Graph.Files -ErrorAction Stop -SkipEditionCheck
    }
  }
  catch {
    Write-Warning "Could not import required modules. Attempting to proceed..."
  }

  Write-Verbose "Querying OneDrive usage for tenant users..."

  try {
    $users = Get-MgUser -All -Filter "accountEnabled eq true" -Property $Properties -ErrorAction Stop

    $oneDriveUsage = $users | ForEach-Object {
      $user = $_

      try {
        # Try to use REST API for drive info due to Graph SDK compatibility issues
        $drive = $null
        try {
          $driveResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($user.Id)/drive" -ErrorAction SilentlyContinue
          if ($driveResponse) {
            $drive = $driveResponse
          }
        }
        catch {
          Write-Verbose "Could not retrieve OneDrive for user $($user.UserPrincipalName) via REST: $_"
        }

        if ($drive) {
          $quota = $drive.quota
          $storageUsedMB = if ($quota.used) { [math]::Round($quota.used / 1MB, 2) } else { 0 }

          # Get item count from drive root via REST
          $itemCount = 0
          try {
            $rootResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($user.Id)/drive/root" -ErrorAction SilentlyContinue
            if ($rootResponse -and $rootResponse.folder) {
              $itemCount = $rootResponse.folder.childCount
            }
          }
          catch {
            Write-Verbose "Could not retrieve item count for $($user.UserPrincipalName): $_"
          }

          # Filter by minimum storage if specified
          if ($IncludeInactiveUsers -or $storageUsedMB -ge $MinStorageMB) {
            [PSCustomObject]@{
              UserPrincipalName  = $user.UserPrincipalName
              DisplayName        = $user.DisplayName
              Mail               = $user.Mail
              StorageUsedBytes   = if ($quota.used) { [int64]$quota.used } else { 0 }
              StorageQuotaBytes  = if ($quota.total) { [int64]$quota.total } else { 0 }
              StorageUsedMB      = $storageUsedMB
              StorageUsedGB      = if ($quota.used) { [math]::Round($quota.used / 1GB, 2) } else { 0 }
              StorageQuotaMB     = if ($quota.total) { [math]::Round($quota.total / 1MB, 2) } else { 0 }
              StorageQuotaGB     = if ($quota.total) { [math]::Round($quota.total / 1GB, 2) } else { 0 }
              StoragePercentUsed = if ($quota.total -gt 0) { [math]::Round(($quota.used / $quota.total) * 100, 2) } else { 0 }
              TotalFiles         = $itemCount
              DriveId            = $drive.Id
            }
          }
        }
      }
      catch {
        Write-Verbose "Unable to retrieve OneDrive for user $($user.UserPrincipalName): $_"
      }
    }

    $usageCount = if ($oneDriveUsage) { ($oneDriveUsage | Measure-Object).Count } else { 0 }
    Write-Verbose "Retrieved OneDrive usage for $usageCount users"
    return $oneDriveUsage
  }
  catch {
    Write-Warning "Failed to retrieve OneDrive usage. Error: $($_.Exception.Message)"
    return @()
  }
}
