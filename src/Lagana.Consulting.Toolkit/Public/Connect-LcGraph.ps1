function Connect-LcGraph {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [string[]]$Scopes = @('Directory.Read.All'),

    [string]$LogPath
  )

  if (-not (Get-Command Connect-MgGraph -ErrorAction SilentlyContinue)) {
    throw "Microsoft.Graph module not found. Install-Module Microsoft.Graph -Scope CurrentUser"
  }

  # Clean slate to avoid cross-tenant context reuse
  if (Get-Command Disconnect-MgGraph -ErrorAction SilentlyContinue) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
  }

  if ($LogPath) { Write-LcLog -Path $LogPath -Level INFO -Message "Connecting to Graph tenant $TenantId with scopes: $($Scopes -join ', ')" }

  Connect-MgGraph -TenantId $TenantId -Scopes $Scopes | Out-Null

  # Verify
  Confirm-LcTenant -TenantId $TenantId -CheckGraph

  if ($LogPath) { Write-LcLog -Path $LogPath -Level INFO -Message "Graph connected and tenant confirmed: $TenantId" }

  return (Get-MgContext)
}
