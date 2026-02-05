function Disconnect-AzCloudTenant {
  <#
  .SYNOPSIS
  Disconnects from Azure AD / Entra ID and clears authentication context.

  .DESCRIPTION
  Closes the MS-Graph connection and removes the stored authentication context.
  Should be called when cloud discovery is complete or switching tenants.

  .EXAMPLE
  DisConnect-AzCloudTenant

  Disconnects from cloud tenant and clears context.

  .INPUTS
  None.

  .OUTPUTS
  None.

  .NOTES
  Safe to call multiple times; does not error if already disconnected.

  .LINK
  Connect-AzCloudTenant
  Get-AzCloudAuthContext
  #>
  [CmdletBinding()]
  param()

  try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    $script:AzCloudAuthContext = $null
    Write-Verbose "Disconnected from cloud tenant and cleared authentication context"
  }
  catch {
    Write-Warning "Error during disconnect: $($_.Exception.Message)"
  }
}
