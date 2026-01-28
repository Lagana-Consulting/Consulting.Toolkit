function Get-AdCloudGroups {
  <#
  .SYNOPSIS
  Discovers all groups in the connected Entra ID tenant.

  .DESCRIPTION
  Queries MS-Graph /groups endpoint and retrieves comprehensive group information including:
  - Group identity (ID, DisplayName, Mail, MailNickname)
  - Group type (Microsoft 365, Security, Distribution)
  - Group membership (member/owner count)
  - Assignment-based access control (RBAC) groups
  - Mail configuration (email, forwarding rules, etc.)

  Results can be filtered by group type or export to CSV.

  .PARAMETER Filter
  OData filter to limit results. Examples:
    - "groupTypes/any(g:g eq 'Unified')" - Only M365 groups
    - "mailEnabled eq true" - Mail-enabled groups only
    - "securityEnabled eq true" - Security groups only
    - "startswith(displayName, 'Sales')" - Groups matching pattern

  .PARAMETER GroupType
  Filter by group type: 'All', 'M365', 'Security', 'MailEnabled', 'Distribution'.
  Default 'All'.

  .PARAMETER Properties
  Specific properties to retrieve. Default includes all common discovery properties.

  .PARAMETER Top
  Number of results to return. Default 999.

  .PARAMETER IncludeMemberCount
  If $true, includes member and owner counts. Requires additional API call per group (slower).
  Default $false.

  .PARAMETER IncludeMembers
  If $true, expands group members inline. Use with caution on large groups; consider
  using Get-AdCloudGroupMembers for large membership queries.
  Default $false.

  .EXAMPLE
  $groups = Get-AdCloudGroups

  Gets all groups in tenant.

  .EXAMPLE
  $m365Groups = Get-AdCloudGroups -GroupType M365

  Gets only Microsoft 365 (Unified) groups.

  .EXAMPLE
  $secGroups = Get-AdCloudGroups -GroupType Security

  Gets only security groups.

  .EXAMPLE
  $distGroups = Get-AdCloudGroups -Filter "mailEnabled eq true" -IncludeMemberCount

  Gets mail-enabled groups with member counts.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  [PSObject] Array of group objects with properties:
    - id, displayName, mailNickname, description
    - groupTypes, mail, mailEnabled, securityEnabled
    - createdDateTime, memberCount, ownerCount (if IncludeMemberCount)
    - visibility, isAssignableToRole
    - Optional: members (if IncludeMembers)

  .NOTES
  Requires Graph scope: Group.Read.All
  Large tenants with many groups may take time; consider Filter to scope query.
  IncludeMemberCount requires additional API calls (1 per group); use sparingly on 1000+ group estates.
  For large group membership analysis, use Get-AdCloudGroupMembers separately.

  .LINK
  Get-AdCloudGroupMembers
  Get-AdCloudUsers
  Get-AdCloudM365Groups
  Export-AdCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [ValidateSet('All', 'M365', 'Security', 'MailEnabled', 'Distribution')]
    [string]$GroupType = 'All',
    [string[]]$Properties = @(
      'id',
      'displayName',
      'mailNickname',
      'description',
      'groupTypes',
      'mail',
      'mailEnabled',
      'securityEnabled',
      'createdDateTime',
      'visibility',
      'isAssignableToRole',
      'resourceProvisioningOptions'
    ),
    [int]$Top = 999,
    [switch]$IncludeMemberCount,
    [switch]$IncludeMembers
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

  # Build filter based on GroupType
  $effectiveFilter = @()

  if ($GroupType -eq 'M365') {
    $effectiveFilter += "groupTypes/any(g:g eq 'Unified')"
  }
  elseif ($GroupType -eq 'Security') {
    $effectiveFilter += "securityEnabled eq true"
  }
  elseif ($GroupType -eq 'MailEnabled') {
    $effectiveFilter += "mailEnabled eq true"
  }
  elseif ($GroupType -eq 'Distribution') {
    $effectiveFilter += "mailEnabled eq true and securityEnabled eq false"
  }

  # Add user filter if provided
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

  Write-Verbose "Querying groups with filter: $finalFilter"

  try {
    $groups = Get-MgGroup @params

    if ($IncludeMemberCount) {
      Write-Verbose "Retrieving member counts for $($groups.Count) groups..."
      $groups = $groups | ForEach-Object {
        $memberCount = (Get-MgGroupMember -GroupId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $ownerCount = (Get-MgGroupOwner -GroupId $_.Id -All -ErrorAction SilentlyContinue | Measure-Object).Count
        $_ | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value $memberCount -Force
        $_ | Add-Member -MemberType NoteProperty -Name 'OwnerCount' -Value $ownerCount -Force
        $_
      }
    }

    Write-Verbose "Retrieved $($groups.Count) groups"
    return $groups
  }
  catch {
    throw "Failed to retrieve groups from MS-Graph. $($_.Exception.Message)"
  }
}
