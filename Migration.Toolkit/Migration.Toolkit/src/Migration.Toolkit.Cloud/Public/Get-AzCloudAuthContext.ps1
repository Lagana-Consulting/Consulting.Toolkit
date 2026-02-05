function Get-AzCloudAuthContext {
  <#
  .SYNOPSIS
  Retrieves the current cloud authentication context.

  .DESCRIPTION
  Returns the stored authentication context created by Connect-AzCloudTenant.
  Useful for validating connection state or retrieving connection details for logging.

  .EXAMPLE
  $ctx = Get-AzCloudAuthContext
  if ($ctx) { Write-Host "Connected to tenant: $($ctx.TenantId)" }

  Retrieves current auth context.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Authentication context or $null if not connected.

  .NOTES
  Returns $null if Connect-AzCloudTenant has not been called.

  .LINK
  Connect-AzCloudTenant
  DisConnect-AzCloudTenant
  #>
  [CmdletBinding()]
  param()

  return $script:AzCloudAuthContext
}
