function Get-AzCloudM365Groups {
  <#
  .SYNOPSIS
  Discovers Microsoft 365 Groups in the connected tenant.

  .DESCRIPTION
  Queries MS-Graph /groups endpoint specifically for Unified (M365) groups and retrieves
  comprehensive information including:
  - Group identity (ID, DisplayName, Mail, MailNickname)
  - Ownership and membership
  - Connected resources (Teams, SharePoint site, Yammer community)
  - Classification and retention
  - Lifecycle state (Active, Archived, Deleted)

  M365 Groups are the hub for Teams, SharePoint, and other collaborative workloads.

  .PARAMETER Filter
  OData filter to limit results.

  .PARAMETER IncludeMembers
  If $true, expands member/owner counts. Default $false.

  .PARAMETER IncludeResources
  If $true, retrieves associated Teams, SharePoint sites, Yammer. Default $false (slower).

  .PARAMETER Properties
  Properties to retrieve.

  .PARAMETER Top
  Number of results. Default 999.

  .EXAMPLE
  $m365Groups = Get-AzCloudM365Groups

  Gets all Microsoft 365 Groups.

  .EXAMPLE
  $activeGroups = Get-AzCloudM365Groups -Filter "createdDateTime ge 2023-01-01T00:00:00Z" -IncludeMembers

  Gets groups created after date with membership info.

  .EXAMPLE
  $groupsWithResources = Get-AzCloudM365Groups -IncludeResources

  Gets all M365 groups and their associated workloads.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of M365 group objects with properties:
    - id, displayName, mail, mailNickname
    - description, createdDateTime, visibility
    - memberCount, ownerCount (if IncludeMembers)
    - teamId, sharePointSiteId, yammerId (if IncludeResources)

  .NOTES
  Requires Graph scope: Group.Read.All
  M365 Groups automatically provision Teams, SharePoint site, shared mailbox.
  Use Get-AzCloudTeams, Get-AzCloudSharePointSites for workload-specific details.

  .LINK
  Get-AzCloudTeams
  Get-AzCloudSharePointSites
  Get-AzCloudGroups
  Get-AzCloudGroupMembers
  Export-AzCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [switch]$IncludeMembers,
    [switch]$IncludeResources,
    [string[]]$Properties = @(
      'id',
      'displayName',
      'mail',
      'mailNickname',
      'description',
      'createdDateTime',
      'visibility',
      'classification',
      'isArchived'
    ),
    [int]$Top = 999
  )

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try { if (-not (Get-Module Microsoft.Graph.Groups -ErrorAction SilentlyContinue)) { Import-Module Microsoft.Graph.Groups -ErrorAction Stop -SkipEditionCheck } } catch { Write-Warning "Could not import Microsoft.Graph.Groups module (may already be loaded). Proceeding..." }

  # Build parameters
  $params = @{
    ErrorAction = 'Stop'
  }

  # Add user-provided filter if specified
  if ($Filter) {
    $params['Filter'] = $Filter
  }

  Write-Verbose "Querying Microsoft 365 (Unified) Groups"

  try {
    # Get groups (limit to reasonable batch size)
    $allGroups = Get-MgGroup @params -Top 999 -ErrorAction Stop

    # Filter to M365 (Unified) groups by checking groupTypes property
    $groups = $allGroups | Where-Object { $_.GroupTypes -contains 'Unified' }

    if ($IncludeMembers) {
      $groupCount = ($groups | Measure-Object).Count
      Write-Verbose "Retrieving member counts for $groupCount groups..."
      $groups = $groups | ForEach-Object {
        $memberCount = (Get-MgGroupMember -GroupId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $ownerCount = (Get-MgGroupOwner -GroupId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $_ | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value $memberCount -Force
        $_ | Add-Member -MemberType NoteProperty -Name 'OwnerCount' -Value $ownerCount -Force
        $_
      }
    }

    if ($IncludeResources) {
      $groupCount2 = ($groups | Measure-Object).Count
      Write-Verbose "Retrieving associated resources for $groupCount2 groups..."
      $groups = $groups | ForEach-Object {
        $groupId = $_.Id

        # Get associated Team (check if group is team-enabled)
        $team = Get-MgTeam -TeamId $groupId -ErrorAction SilentlyContinue
        if ($team) {
          $_ | Add-Member -MemberType NoteProperty -Name 'TeamId' -Value $team.Id -Force
        }

        # Get associated SharePoint site (via drive)
        $drive = Get-MgGroupDrive -GroupId $groupId -ErrorAction SilentlyContinue
        if ($drive) {
          $_ | Add-Member -MemberType NoteProperty -Name 'DriveId' -Value $drive.Id -Force
        }

        $_
      }
    }

    # Always add storage and file count from associated SharePoint site
    Write-Verbose "Retrieving storage and file count for $($groups.Count) M365 groups..."
    $groups = $groups | ForEach-Object {
      $group = $_

      try {
        # Get the associated SharePoint site (M365 groups automatically provision SharePoint)
        $site = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($group.Id)/sites/root" -ErrorAction SilentlyContinue

        if ($site) {
          # Get drives for this site
          $drives = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($site.id)/drives" -ErrorAction SilentlyContinue

          $totalStorage = 0
          $totalFiles = 0

          if ($drives -and $drives.value) {
            foreach ($drive in $drives.value) {
              if ($drive.quota) {
                $totalStorage += $drive.quota.used
              }
              # Get item count
              try {
                $driveRoot = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$($drive.id)/root" -ErrorAction SilentlyContinue
                if ($driveRoot -and $driveRoot.folder) {
                  $totalFiles += $driveRoot.folder.childCount
                }
              }
              catch {
                Write-Verbose "Could not get file count for M365 group $($group.DisplayName) drive: $_"
              }
            }
          }

          $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedBytes' -Value $totalStorage -Force -ErrorAction SilentlyContinue
          $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedMB' -Value ([math]::Round($totalStorage / 1MB, 2)) -Force -ErrorAction SilentlyContinue
          $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedGB' -Value ([math]::Round($totalStorage / 1GB, 2)) -Force -ErrorAction SilentlyContinue
          $group | Add-Member -MemberType NoteProperty -Name 'TotalFiles' -Value $totalFiles -Force -ErrorAction SilentlyContinue
        }
        else {
          # No site found, set defaults
          $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedBytes' -Value 0 -Force -ErrorAction SilentlyContinue
          $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedMB' -Value 0 -Force -ErrorAction SilentlyContinue
          $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedGB' -Value 0 -Force -ErrorAction SilentlyContinue
          $group | Add-Member -MemberType NoteProperty -Name 'TotalFiles' -Value 0 -Force -ErrorAction SilentlyContinue
        }
      }
      catch {
        Write-Verbose "Could not retrieve storage info for M365 group $($group.DisplayName): $_"
        $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedBytes' -Value 0 -Force -ErrorAction SilentlyContinue
        $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedMB' -Value 0 -Force -ErrorAction SilentlyContinue
        $group | Add-Member -MemberType NoteProperty -Name 'StorageUsedGB' -Value 0 -Force -ErrorAction SilentlyContinue
        $group | Add-Member -MemberType NoteProperty -Name 'TotalFiles' -Value 0 -Force -ErrorAction SilentlyContinue
      }

      $group
    }

    $finalCount = if ($groups) { ($groups | Measure-Object).Count } else { 0 }
    Write-Verbose "Retrieved $finalCount M365 groups"
    return $groups
  }
  catch {
    Write-Warning "Failed to retrieve M365 groups. Error: $($_.Exception.Message)"
    return @()
  }
}
