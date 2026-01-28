function Get-AdCloudAuthContext {
  <#
  .SYNOPSIS
  Retrieves the current cloud authentication context.

  .DESCRIPTION
  Returns the stored authentication context created by Connect-AdCloudTenant.
  Useful for validating connection state or retrieving connection details for logging.

  .EXAMPLE
  $ctx = Get-AdCloudAuthContext
  if ($ctx) { Write-Host "Connected to tenant: $($ctx.TenantId)" }

  Retrieves current auth context.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Authentication context or $null if not connected.

  .NOTES
  Returns $null if Connect-AdCloudTenant has not been called.

  .LINK
  Connect-AdCloudTenant
  Disconnect-AdCloudTenant
  #>
  [CmdletBinding()]
  param()

  return $script:AdCloudAuthContext
}
