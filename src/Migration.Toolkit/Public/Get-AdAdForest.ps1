function Get-AdAdForest {
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
    $target = if ($ForestName) { $ForestName } else { 'current forest' }
    throw "Failed to query AD forest ($target). $($_.Exception.Message)"
  }
}
