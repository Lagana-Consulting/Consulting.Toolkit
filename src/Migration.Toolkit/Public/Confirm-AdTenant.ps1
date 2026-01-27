function Confirm-AdTenant {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [switch]$CheckGraph,
    [switch]$CheckAz
  )

  $ok = $true

  if ($CheckGraph) {
    if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
      $ctx = Get-MgContext
      if (-not $ctx -or -not $ctx.TenantId) {
        throw "Microsoft Graph context not found. Run Connect-MgGraph first (or use Connect-AdGraph)."
      }
      if ($ctx.TenantId -ne $TenantId) {
        throw "Wrong Graph tenant. Expected: $TenantId  Actual: $($ctx.TenantId)"
      }
    } else {
      throw "Microsoft.Graph PowerShell SDK not available. Install-Module Microsoft.Graph"
    }
  }

  if ($CheckAz) {
    if (Get-Command Get-AzContext -ErrorAction SilentlyContinue) {
      $az = Get-AzContext
      if (-not $az -or -not $az.Tenant) {
        throw "Azure context not found. Run Connect-AzAccount."
      }
      if ($az.Tenant.Id -ne $TenantId) {
        throw "Wrong Azure tenant. Expected: $TenantId  Actual: $($az.Tenant.Id)"
      }
    } else {
      throw "Az.Accounts not available. Install-Module Az.Accounts"
    }
  }

  return $ok
}
