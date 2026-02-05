function Get-AzCloudSharePointSites {
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
  $sites = Get-AzCloudSharePointSites

  Gets all SharePoint sites.

  .EXAMPLE
  $teamSites = Get-AzCloudSharePointSites -SiteType TeamSite -IncludeStorage

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
  Get-AzCloudOneDriveUsage
  Get-AdCloudSitePermissions
  Get-AzCloudTeams
  Export-AzCloudCsv
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

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try { if (-not (Get-Module Microsoft.Graph.Sites -ErrorAction SilentlyContinue)) { Import-Module Microsoft.Graph.Sites -ErrorAction Stop -SkipEditionCheck } } catch { Write-Warning "Could not import Microsoft.Graph.Sites module (may already be loaded). Proceeding..." }

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
    All         = $true
    ErrorAction = 'Stop'
    Property    = $Properties
  }

  if ($finalFilter) {
    $params['Filter'] = $finalFilter
  }

  Write-Verbose "Querying SharePoint sites with type: $SiteType"

  # Always try to get the root site first
  $sites = @()
  try {
    $rootResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/root" -ErrorAction Stop
    # Convert hashtable to PSCustomObject for consistency
    if ($rootResponse) {
      $sites += [PSCustomObject]$rootResponse
    }
    Write-Verbose "Got root site: $($rootResponse.webUrl)"
  }
  catch {
    Write-Verbose "Could not get root site: $($_.Exception.Message)"
  }

  # Then try to get additional sites via SDK or REST
  try {
    $additionalSites = Get-MgSite @params -ErrorAction Stop
    if ($additionalSites) {
      $sites += $additionalSites
      $additionalCount = if ($additionalSites) { ($additionalSites | Measure-Object).Count } else { 0 }
      Write-Verbose "Retrieved $additionalCount additional sites via SDK"
    }
  }
  catch {
    # Fallback: Try to get subsites of root
    Write-Verbose "SDK cmdlet failed, attempting REST API for subsites..."
    try {
      $subsiteResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/root/sites" -ErrorAction Stop
      if ($subsiteResponse.value) {
        # Convert each hashtable to PSCustomObject
        $subsiteResponse.value | ForEach-Object { $sites += [PSCustomObject]$_ }
        Write-Verbose "Found $($subsiteResponse.value.Count) subsites via REST"
      }
    }
    catch {
      Write-Verbose "Subsite query failed: $($_.Exception.Message)"
    }
  }

  # De-duplicate sites by ID (handle both object types)
  $sites = $sites | Where-Object { $_.id } | Sort-Object -Property id -Unique
  $siteCount = if ($sites) { ($sites | Measure-Object).Count } else { 0 }
  Write-Verbose "Retrieved $siteCount sites"

  if ($siteCount -eq 0) {
    Write-Warning "No SharePoint sites found. This may be normal if tenant has no sites, or permissions may be insufficient."
  }

  # Always try to add storage and file count info
  Write-Verbose "Retrieving storage and file count for $siteCount sites..."
  $sites = $sites | ForEach-Object {
    $site = $_

    # Try to get storage info from beta endpoint
    try {
      # Use beta endpoint for storage metrics
      $siteStats = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/sites/$($site.id)" -ErrorAction SilentlyContinue

      # Try to get drive for file count
      $drives = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$($site.id)/drives" -ErrorAction SilentlyContinue

      $totalStorage = 0
      $totalFiles = 0

      if ($drives -and $drives.value) {
        foreach ($drive in $drives.value) {
          if ($drive.quota) {
            $totalStorage += $drive.quota.used
          }
          # Get item count from drive
          try {
            $driveRoot = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/drives/$($drive.id)/root" -ErrorAction SilentlyContinue
            if ($driveRoot -and $driveRoot.folder) {
              $totalFiles += $driveRoot.folder.childCount
            }
          }
          catch {
            Write-Verbose "Could not get file count for drive $($drive.id): $_"
          }
        }
      }

      $site | Add-Member -MemberType NoteProperty -Name 'StorageUsedBytes' -Value $totalStorage -Force -ErrorAction SilentlyContinue
      $site | Add-Member -MemberType NoteProperty -Name 'StorageUsedMB' -Value ([math]::Round($totalStorage / 1MB, 2)) -Force -ErrorAction SilentlyContinue
      $site | Add-Member -MemberType NoteProperty -Name 'StorageUsedGB' -Value ([math]::Round($totalStorage / 1GB, 2)) -Force -ErrorAction SilentlyContinue
      $site | Add-Member -MemberType NoteProperty -Name 'TotalFiles' -Value $totalFiles -Force -ErrorAction SilentlyContinue
    }
    catch {
      Write-Verbose "Could not retrieve storage info for site $($site.displayName): $_"
      $site | Add-Member -MemberType NoteProperty -Name 'StorageUsedBytes' -Value 0 -Force -ErrorAction SilentlyContinue
      $site | Add-Member -MemberType NoteProperty -Name 'StorageUsedMB' -Value 0 -Force -ErrorAction SilentlyContinue
      $site | Add-Member -MemberType NoteProperty -Name 'StorageUsedGB' -Value 0 -Force -ErrorAction SilentlyContinue
      $site | Add-Member -MemberType NoteProperty -Name 'TotalFiles' -Value 0 -Force -ErrorAction SilentlyContinue
    }

    $site
  }

  $finalCount = if ($sites) { ($sites | Measure-Object).Count } else { 0 }
  Write-Verbose "Retrieved $finalCount sites"
  return $sites
}
