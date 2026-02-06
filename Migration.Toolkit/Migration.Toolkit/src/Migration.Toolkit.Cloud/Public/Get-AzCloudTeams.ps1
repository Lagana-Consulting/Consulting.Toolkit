function Get-AzCloudTeams {
  <#
  .SYNOPSIS
  Discovers all Teams in the connected tenant.

  .DESCRIPTION
  Queries MS-Graph /teams endpoint and retrieves comprehensive Teams information including:
  - Team identity (ID, DisplayName, Description)
  - Team type (Private, Public, Shared channels)
  - Membership (owner, member counts)
  - Configuration (Guest access, Retention policies)
  - Channel count and activity

  .PARAMETER Filter
  OData filter to limit results. Examples:
    - "displayName eq 'Engineering'" - Specific team
    - "startswith(displayName, 'Project')" - Teams matching pattern

  .PARAMETER IncludeChannels
  If $true, includes channel count. Default $false.

  .PARAMETER IncludeMembers
  If $true, expands member/owner counts. Default $false.

  .PARAMETER Properties
  Properties to retrieve.

  .PARAMETER Top
  Number of results. Default 999.

  .EXAMPLE
  $teams = Get-AzCloudTeams

  Gets all Teams in tenant.

  .EXAMPLE
  $teamsByName = Get-AzCloudTeams -Filter "displayName eq 'Engineering'" -IncludeChannels -IncludeMembers

  Gets specific team with channel and member counts.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of team objects with properties:
    - id, displayName, description
    - isArchived, createdDateTime
    - channelCount (if IncludeChannels)
    - memberCount, ownerCount (if IncludeMembers)

  .NOTES
  Requires Graph scope: Team.ReadBasic.All or TeamSettings.Read.All
  Large tenants may have 1000s of teams; use Filter to scope.

  .LINK
  Get-AdCloudTeamChannels
  Get-AdCloudTeamMembers
  Get-AzCloudM365Groups
  Export-AzCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [switch]$IncludeChannels,
    [switch]$IncludeMembers,
    [string[]]$Properties = @(
      'id',
      'displayName',
      'description',
      'isArchived',
      'createdDateTime',
      'visibility'
    ),
    [int]$Top = 999
  )

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try { if (-not (Get-Module Microsoft.Graph.Teams -ErrorAction SilentlyContinue)) { Import-Module Microsoft.Graph.Teams -ErrorAction Stop -SkipEditionCheck } } catch { Write-Warning "Could not import Microsoft.Graph.Teams module (may already be loaded). Proceeding..." }

  $params = @{
    All = $true
    ErrorAction = 'Stop'
    Property = $Properties
  }

  if ($Filter) {
    $params['Filter'] = $Filter
  }

  Write-Verbose "Querying Teams with filter: $($params['Filter'] -or 'none')"

  try {
    $teams = Get-MgTeam @params

    if ($IncludeChannels) {
      Write-Verbose "Retrieving channel counts for $($teams.Count) teams..."
      $teams = $teams | ForEach-Object {
        $channelCount = (Get-MgTeamChannel -TeamId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $_ | Add-Member -MemberType NoteProperty -Name 'ChannelCount' -Value $channelCount -Force
        $_
      }
    }

    if ($IncludeMembers) {
      Write-Verbose "Retrieving member counts for $($teams.Count) teams..."
      $teams = $teams | ForEach-Object {
        $memberCount = (Get-MgTeamMember -TeamId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $_ | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value $memberCount -Force
        $_
      }
    }

    # Add storage and file count from associated SharePoint site
    Write-Verbose "Retrieving storage and file count for $($teams.Count) teams..."
    $teams = $teams | ForEach-Object {
      $team = $_

      try {
        # Get the team's group to find the associated SharePoint site
        $group = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($team.Id)" -ErrorAction SilentlyContinue

        if ($group) {
          # Get associated SharePoint site
          $site = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($team.Id)/sites/root" -ErrorAction SilentlyContinue

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
                  Write-Verbose "Could not get file count for team $($team.DisplayName) drive: $_"
                }
              }
            }

            $team | Add-Member -MemberType NoteProperty -Name 'StorageUsedBytes' -Value $totalStorage -Force -ErrorAction SilentlyContinue
            $team | Add-Member -MemberType NoteProperty -Name 'StorageUsedMB' -Value ([math]::Round($totalStorage / 1MB, 2)) -Force -ErrorAction SilentlyContinue
            $team | Add-Member -MemberType NoteProperty -Name 'StorageUsedGB' -Value ([math]::Round($totalStorage / 1GB, 2)) -Force -ErrorAction SilentlyContinue
            $team | Add-Member -MemberType NoteProperty -Name 'TotalFiles' -Value $totalFiles -Force -ErrorAction SilentlyContinue
          }
        }
      }
      catch {
        Write-Verbose "Could not retrieve storage info for team $($team.DisplayName): $_"
        $team | Add-Member -MemberType NoteProperty -Name 'StorageUsedBytes' -Value 0 -Force -ErrorAction SilentlyContinue
        $team | Add-Member -MemberType NoteProperty -Name 'StorageUsedMB' -Value 0 -Force -ErrorAction SilentlyContinue
        $team | Add-Member -MemberType NoteProperty -Name 'StorageUsedGB' -Value 0 -Force -ErrorAction SilentlyContinue
        $team | Add-Member -MemberType NoteProperty -Name 'TotalFiles' -Value 0 -Force -ErrorAction SilentlyContinue
      }

      $team
    }

    Write-Verbose "Retrieved $($teams.Count) teams"
    return $teams
  }
  catch {
    throw "Failed to retrieve Teams from MS-Graph. $($_.Exception.Message)"
  }
}
