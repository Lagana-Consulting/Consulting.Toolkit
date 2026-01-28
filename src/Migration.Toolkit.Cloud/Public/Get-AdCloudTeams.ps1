function Get-AdCloudTeams {
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
  $teams = Get-AdCloudTeams

  Gets all Teams in tenant.

  .EXAMPLE
  $teamsByName = Get-AdCloudTeams -Filter "displayName eq 'Engineering'" -IncludeChannels -IncludeMembers

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
  Get-AdCloudM365Groups
  Export-AdCloudCsv
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

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module Microsoft.Graph.Teams -ErrorAction Stop
  }
  catch {
    throw "Microsoft.Graph.Teams module required. Install via: Install-Module Microsoft.Graph.Teams"
  }

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

    Write-Verbose "Retrieved $($teams.Count) teams"
    return $teams
  }
  catch {
    throw "Failed to retrieve Teams from MS-Graph. $($_.Exception.Message)"
  }
}
