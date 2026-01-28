function Get-AdCloudTenantInfo {
  <#
  .SYNOPSIS
  Retrieves basic tenant information for the connected cloud tenant.

  .DESCRIPTION
  Queries MS-Graph for organizational settings and returns tenant metadata useful
  for discovery context and reporting.

  .EXAMPLE
  $tenantInfo = Get-AdCloudTenantInfo

  Gets tenant information.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Tenant information object with properties:
    - TenantId, DisplayName, VerifiedDomains, DefaultDomainName
    - CreatedDateTime, LicenseCount

  .NOTES
  Requires connection via Connect-AdCloudTenant.

  .LINK
  Connect-AdCloudTenant
  Get-AdCloudAuthContext
  #>
  [CmdletBinding()]
  param()

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module Microsoft.Graph.Organization -ErrorAction Stop
  }
  catch {
    throw "Microsoft.Graph.Organization module required. Install via: Install-Module Microsoft.Graph.Organization"
  }

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
