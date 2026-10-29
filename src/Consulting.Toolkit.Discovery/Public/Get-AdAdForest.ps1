function Get-AdAdForest {
  <#
  .SYNOPSIS
  Retrieves Active Directory forest information.

  .DESCRIPTION
  Gets detailed information about the specified AD forest, including domains, sites,
  functional level, and schema version. Wraps Get-ADForest with enhanced error handling.
  Requires RSAT Active Directory module.

  .PARAMETER ForestName
  Name of the forest to query. If not specified, queries the current forest context.

  .PARAMETER Server
  Domain controller or global catalog to query. Useful in locked-down networks or
  when querying cross-forest. Optional.

  .EXAMPLE
  Get-AdAdForest

  Gets information about the current forest.

  .EXAMPLE
  Get-AdAdForest -ForestName "contoso.com"

  Gets information about the contoso.com forest.

  .EXAMPLE
  Get-AdAdForest -ForestName "fabrikam.com" -Server "gc.fabrikam.com"

  Queries fabrikam.com forest using a specific global catalog server.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  Microsoft.ActiveDirectory.Management.ADForest
  Forest object with properties: Domains, Sites, ForestMode, SchemaMaster, etc.

  .NOTES
  Requires Active Directory PowerShell module (RSAT).
  Throws descriptive errors if forest is unreachable or module is unavailable.

  .LINK
  Get-ADForest
  Get-AdAdDomains
  #>
  [CmdletBinding()]
  param(
    # Optional: specify a forest name if you need to target something other than current context
    [string]$ForestName,

    # Optional: specify a DC/GC to query against (useful in locked-down networks)
    [string]$Server
  )

  if (-not (Get-Command Get-ADForest -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $params = @{}
  if ($ForestName) { $params['Identity'] = $ForestName }
  if ($Server)     { $params['Server']   = $Server }

  try {
    return (Get-ADForest @params -ErrorAction Stop)
  } catch {
    throw
  }
}
