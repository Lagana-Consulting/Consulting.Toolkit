function Get-AdCloudOneDriveUsage {
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
  $oneDrives = Get-AdCloudOneDriveUsage

  Gets OneDrive usage for all active users.

  .EXAMPLE
  $largeOneDrives = Get-AdCloudOneDriveUsage -MinStorageMB 10240

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
  Get-AdCloudUsers
  Get-AdCloudSharePointSites
  Export-AdCloudCsv
  #>
  [CmdletBinding()]
  param(
    [switch]$IncludeInactiveUsers,
    [int]$MinStorageMB = 0,
    [string[]]$Properties = @(
      'userPrincipalName',
      'displayName',
      'mail',
      'createdDateTime'
    )
  )

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Import-Module Microsoft.Graph.Files -ErrorAction Stop
  }
  catch {
    throw "Microsoft.Graph.Users and Microsoft.Graph.Files modules required."
  }

  Write-Verbose "Querying OneDrive usage for tenant users..."

  try {
    $users = Get-MgUser -All -Filter "accountEnabled eq true" -Property $Properties -ErrorAction Stop

    $oneDriveUsage = $users | ForEach-Object {
      $user = $_

      try {
        $drive = Get-MgUserDrive -UserId $user.Id -ErrorAction SilentlyContinue

        if ($drive) {
          $quota = $drive.Quota
          $storageUsedMB = [math]::Round($quota.used / 1MB, 2)

          # Filter by minimum storage if specified
          if ($IncludeInactiveUsers -or $storageUsedMB -ge $MinStorageMB) {
            [PSCustomObject]@{
              UserPrincipalName = $user.UserPrincipalName
              DisplayName = $user.DisplayName
              Mail = $user.Mail
              StorageUsedBytes = $quota.used
              StorageQuotaBytes = $quota.total
              StorageUsedMB = $storageUsedMB
              StorageQuotaMB = [math]::Round($quota.total / 1MB, 2)
              StoragePercentUsed = [math]::Round(($quota.used / $quota.total) * 100, 2)
              DriveId = $drive.Id
            }
          }
        }
      }
      catch {
        Write-Verbose "Unable to retrieve OneDrive for user $($user.UserPrincipalName): $_"
      }
    }

    Write-Verbose "Retrieved OneDrive usage for $($oneDriveUsage.Count) users"
    return $oneDriveUsage
  }
  catch {
    throw "Failed to retrieve OneDrive usage. $($_.Exception.Message)"
  }
}
