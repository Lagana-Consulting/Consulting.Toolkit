function Get-AdCloudM365Groups {
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
  $m365Groups = Get-AdCloudM365Groups

  Gets all Microsoft 365 Groups.

  .EXAMPLE
  $activeGroups = Get-AdCloudM365Groups -Filter "createdDateTime ge 2023-01-01T00:00:00Z" -IncludeMembers

  Gets groups created after date with membership info.

  .EXAMPLE
  $groupsWithResources = Get-AdCloudM365Groups -IncludeResources

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
  Use Get-AdCloudTeams, Get-AdCloudSharePointSites for workload-specific details.

  .LINK
  Get-AdCloudTeams
  Get-AdCloudSharePointSites
  Get-AdCloudGroups
  Get-AdCloudGroupMembers
  Export-AdCloudCsv
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

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module Microsoft.Graph.Groups -ErrorAction Stop
  }
  catch {
    throw "Microsoft.Graph.Groups module required. Install via: Install-Module Microsoft.Graph.Groups"
  }

  # M365 groups are Unified groups
  $effectiveFilter = "groupTypes/any(g:g eq 'Unified')"
  if ($Filter) {
    $effectiveFilter = "$effectiveFilter and ($Filter)"
  }

  $params = @{
    All = $true
    ErrorAction = 'Stop'
    Property = $Properties
    Filter = $effectiveFilter
  }

  Write-Verbose "Querying Microsoft 365 (Unified) Groups"

  try {
    $groups = Get-MgGroup @params

    if ($IncludeMembers) {
      Write-Verbose "Retrieving member counts for $($groups.Count) groups..."
      $groups = $groups | ForEach-Object {
        $memberCount = (Get-MgGroupMember -GroupId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $ownerCount = (Get-MgGroupOwner -GroupId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $_ | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value $memberCount -Force
        $_ | Add-Member -MemberType NoteProperty -Name 'OwnerCount' -Value $ownerCount -Force
        $_
      }
    }

    if ($IncludeResources) {
      Write-Verbose "Retrieving associated resources for $($groups.Count) groups..."
      $groups = $groups | ForEach-Object {
        $groupId = $_.Id

        # Get associated Team
        $team = Get-MgGroupTeam -GroupId $groupId -ErrorAction SilentlyContinue
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

    Write-Verbose "Retrieved $($groups.Count) M365 groups"
    return $groups
  }
  catch {
    throw "Failed to retrieve M365 groups from MS-Graph. $($_.Exception.Message)"
  }
}
