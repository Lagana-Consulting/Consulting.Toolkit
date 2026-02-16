function Get-AzCloudTenantInfo {
  <#
  .SYNOPSIS
  Retrieves basic tenant information for the connected cloud tenant.

  .DESCRIPTION
  Queries MS-Graph for organizational settings and returns tenant metadata useful
  for discovery context and reporting.

  .EXAMPLE
  $tenantInfo = Get-AzCloudTenantInfo

  Gets tenant information.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Tenant information object with properties:
    - TenantId, DisplayName, VerifiedDomains, DefaultDomainName
    - CreatedDateTime, LicenseCount

  .NOTES
  Requires connection via Connect-AzCloudTenant.

  .LINK
  Connect-AzCloudTenant
  Get-AzCloudAuthContext
  #>
  [CmdletBinding()]
  param()

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try { if (-not (Get-Module Microsoft.Graph.Organization -ErrorAction SilentlyContinue)) { Import-Module Microsoft.Graph.Organization -ErrorAction Stop -SkipEditionCheck } } catch { Write-Warning "Could not import Microsoft.Graph.Organization module (may already be loaded). Proceeding..." }

  try {
    $org = Get-MgOrganization -ErrorAction Stop

    return [PSCustomObject]@{
      TenantId = $org.Id
      DisplayName = $org.DisplayName
      VerifiedDomains = $org.VerifiedDomains
      TenantType = $org.TenantType
      CreatedDateTime = $org.CreatedDateTime
    }
  }
  catch {
    throw "Failed to retrieve tenant information. $($_.Exception.Message)"
  }
}
