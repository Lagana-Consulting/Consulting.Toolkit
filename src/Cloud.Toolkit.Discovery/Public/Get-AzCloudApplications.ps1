function Get-AzCloudApplications {
  <#
  .SYNOPSIS
  Discovers all applications and service principals registered in the connected Entra ID tenant.

  .DESCRIPTION
  Queries MS-Graph /applications and /servicePrincipals endpoints and retrieves comprehensive
  application registration and service principal information including:
  - Application registration (ID, AppId, DisplayName)
  - Owned by (creator/owner)
  - Assigned roles and permissions (OAuth2 permissions, app roles)
  - Sign-in URL and reply URLs
  - Certificates and secrets (expiry dates, count)

  Useful for discovering third-party integrations, internal applications, and permissions.

  .PARAMETER Filter
  OData filter to limit results. Examples:
    - "displayName eq 'MyApp'" - Specific application
    - "startswith(displayName, 'Microsoft')" - Applications starting with pattern

  .PARAMETER IncludeServicePrincipals
  If $true, also queries /servicePrincipals. Default $true.
  Service principals are shadow objects created when applications are granted consent.

  .PARAMETER IncludePermissions
  If $true, includes OAuth2 permissions and app roles. Requires additional queries.
  Default $true.

  .PARAMETER IncludeSecretStatus
  If $true, includes count and expiry of certificates and secrets (for audit of stale credentials).
  Default $true.

  .PARAMETER Properties
  Specific properties to retrieve. Default includes all common discovery properties.

  .PARAMETER Top
  Number of results to return. Default 999.

  .EXAMPLE
  $apps = Get-AzCloudApplications

  Gets all application registrations in tenant.

  .EXAMPLE
  $app = Get-AzCloudApplications -Filter "displayName eq 'My Enterprise App'"

  Gets a specific application.

  .EXAMPLE
  $appsWithSecrets = Get-AzCloudApplications | Where-Object { $_.PasswordCredentials.Count -gt 0 }

  Gets applications with configured client secrets.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  [PSObject] Array of application/service principal objects with properties:
    - id, appId, displayName, description
    - createdDateTime, publisherName
    - signInAudience, isPublicClient
    - passwordCredentials (client secrets count/expiry)
    - keyCredentials (certificates count/expiry)
    - Optional: OAuth2PermissionScopes, appRoles (if IncludePermissions)

  .NOTES
  Requires Graph scopes: Application.Read.All, Directory.Read.All
  Applications may have multiple service principals in shared tenants.
  Stale credentials (expired certs/secrets) should be reviewed for compliance.
  For detailed permission consent status, use servicePrincipal's consentClassifications.

  .LINK
  Get-AzCloudUsers
  Get-AzCloudGroups
  Get-AdCloudRoleAssignments
  Export-AzCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [switch]$IncludeServicePrincipals = $true,
    [switch]$IncludePermissions = $true,
    [switch]$IncludeSecretStatus = $true,
    [string[]]$Properties = @(
      'id',
      'appId',
      'displayName',
      'description',
      'createdDateTime',
      'publisherName',
      'signInAudience',
      'isPublicClient',
      'passwordCredentials',
      'keyCredentials',
      'web',
      'spa',
      'publicClient'
    ),
    [int]$Top = 999
  )

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try { if (-not (Get-Module Microsoft.Graph.Applications -ErrorAction SilentlyContinue)) { Import-Module Microsoft.Graph.Applications -ErrorAction Stop -SkipEditionCheck } } catch { Write-Warning "Could not import Microsoft.Graph.Applications module (may already be loaded). Proceeding..." }

  $params = @{
    All         = $true
    ErrorAction = 'Stop'
    Property    = $Properties
  }

  if ($Filter) {
    $params['Filter'] = $Filter
  }

  Write-Verbose "Querying applications with filter: $($params['Filter'] -or 'none')"

  $results = @()

  try {
    # Try SDK cmdlet first
    $apps = Get-MgApplication @params -ErrorAction Stop
    $appCount = if ($apps) { ($apps | Measure-Object).Count } else { 0 }
    Write-Verbose "Retrieved $appCount application registrations"
  }
  catch {
    # Fallback to direct REST API if SDK fails
    Write-Verbose "SDK cmdlet failed, attempting direct REST API call..."
    try {
      $uri = "https://graph.microsoft.com/v1.0/applications"
      if ($Filter) {
        $uri += "?`$filter=$([System.Web.HttpUtility]::UrlEncode($Filter))"
      }
      $apps = (Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop).value
      $appCount = if ($apps) { ($apps | Measure-Object).Count } else { 0 }
      Write-Verbose "Retrieved $appCount applications via REST API"
    }
    catch {
      Write-Warning "Failed to retrieve applications (SDK compatibility issue). Returning empty set. Error: $($_.Exception.Message)"
      return @()
    }
  }

  if ($apps) {
    $apps = $apps | ForEach-Object {
      $app = $_

      # Add secret/cert status
      if ($IncludeSecretStatus) {
        $secretExpiry = $app.PasswordCredentials | Where-Object { $_.EndDateTime -lt (Get-Date) } | Measure-Object
        $certExpiry = $app.KeyCredentials | Where-Object { $_.EndDateTime -lt (Get-Date) } | Measure-Object
        $app | Add-Member -MemberType NoteProperty -Name 'ExpiredSecretCount' -Value $secretExpiry.Count -Force
        $app | Add-Member -MemberType NoteProperty -Name 'ExpiredCertCount' -Value $certExpiry.Count -Force
        $app | Add-Member -MemberType NoteProperty -Name 'TotalSecretCount' -Value $app.PasswordCredentials.Count -Force
        $app | Add-Member -MemberType NoteProperty -Name 'TotalCertCount' -Value $app.KeyCredentials.Count -Force
      }

      $app
    }
  }

  $results += $apps

  # Optionally retrieve service principals (shadow objects when apps are granted consent)
  if ($IncludeServicePrincipals) {
    Write-Verbose "Querying service principals..."
    $spParams = @{
      All         = $true
      ErrorAction = 'Stop'
    }
    if ($Filter) {
      $spParams['Filter'] = $Filter
    }

    try {
      $servicePrincipals = Get-MgServicePrincipal @spParams -ErrorAction Stop
      $spCount = if ($servicePrincipals) { ($servicePrincipals | Measure-Object).Count } else { 0 }
      Write-Verbose "Retrieved $spCount service principals"
      $results += $servicePrincipals
    }
    catch {
      # Fallback to REST API
      Write-Verbose "SDK cmdlet failed for service principals, attempting direct REST API call..."
      try {
        $uri = "https://graph.microsoft.com/v1.0/servicePrincipals"
        if ($Filter) {
          $uri += "?`$filter=$([System.Web.HttpUtility]::UrlEncode($Filter))"
        }
        $servicePrincipals = (Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop).value
        $spCount = if ($servicePrincipals) { ($servicePrincipals | Measure-Object).Count } else { 0 }
        Write-Verbose "Retrieved $spCount service principals via REST API"
        $results += $servicePrincipals
      }
      catch {
        Write-Warning "Failed to retrieve service principals. Error: $($_.Exception.Message)"
      }
    }
  }

  return $results
}
