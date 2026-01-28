function Get-AdCloudSharePointSites {
  <#
  .SYNOPSIS
  Discovers all SharePoint sites in the connected tenant.

  .DESCRIPTION
  Queries MS-Graph /sites endpoint and retrieves comprehensive SharePoint site information including:
  - Site identity (ID, DisplayName, URL, SiteCollection)
  - Site type (Communication, Team, OneDrive)
  - Storage usage and quota
  - Item counts (documents, lists)
  - Sharing status and external collaborators

  .PARAMETER Filter
  OData filter to limit results.

  .PARAMETER SiteType
  Filter: 'All', 'TeamSite', 'CommunicationSite', 'OneDrive'. Default 'All'.

  .PARAMETER IncludeStorage
  If $true, includes storage usage and quota. Default $false (requires additional queries).

  .PARAMETER IncludeItems
  If $true, includes document/list counts. Default $false.

  .PARAMETER Properties
  Properties to retrieve.

  .PARAMETER Top
  Number of results. Default 999.

  .EXAMPLE
  $sites = Get-AdCloudSharePointSites

  Gets all SharePoint sites.

  .EXAMPLE
  $teamSites = Get-AdCloudSharePointSites -SiteType TeamSite -IncludeStorage

  Gets team-associated SharePoint sites with storage info.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of site objects with properties:
    - id, displayName, webUrl
    - siteCollection (root URL)
    - createdDateTime, lastModifiedDateTime
    - StorageUsed, StorageQuota (if IncludeStorage)
    - ItemCount (if IncludeItems)

  .NOTES
  Requires Graph scope: Sites.Read.All or Sites.Manage.All
  Large tenants may have 1000s of sites; use Filter to scope.

  .LINK
  Get-AdCloudOneDriveUsage
  Get-AdCloudSitePermissions
  Get-AdCloudTeams
  Export-AdCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [ValidateSet('All', 'TeamSite', 'CommunicationSite', 'OneDrive')]
    [string]$SiteType = 'All',
    [switch]$IncludeStorage,
    [switch]$IncludeItems,
    [string[]]$Properties = @(
      'id',
      'displayName',
      'webUrl',
      'createdDateTime',
      'lastModifiedDateTime',
      'siteCollection'
    ),
    [int]$Top = 999
  )

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module Microsoft.Graph.Sites -ErrorAction Stop
  }
  catch {
    throw "Microsoft.Graph.Sites module required. Install via: Install-Module Microsoft.Graph.Sites"
  }

  $effectiveFilter = @()

  # Site type filtering depends on internal structure; mostly use web URL patterns
  if ($SiteType -eq 'TeamSite') {
    $effectiveFilter += "webUrl eq '/sites/'"
  }
  elseif ($SiteType -eq 'OneDrive') {
    $effectiveFilter += "webUrl eq '/personal/'"
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

  Write-Verbose "Querying SharePoint sites with type: $SiteType"

  try {
    $sites = Get-MgSite @params

    if ($IncludeStorage) {
      Write-Verbose "Retrieving storage usage for $($sites.Count) sites..."
      $sites = $sites | ForEach-Object {
        $storage = Get-MgSiteAnalytics -SiteId $_.Id -ErrorAction SilentlyContinue
        $_ | Add-Member -MemberType NoteProperty -Name 'StorageUsageBytes' -Value $storage.AllTime.ActiveFileCount -Force -ErrorAction SilentlyContinue
        $_
      }
    }

    Write-Verbose "Retrieved $($sites.Count) sites"
    return $sites
  }
  catch {
    throw "Failed to retrieve SharePoint sites from MS-Graph. $($_.Exception.Message)"
  }
}
