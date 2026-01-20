function Get-LcAdForestTrusts {
  [CmdletBinding()]
  param(
    [string]$ForestName,
    [string]$Server,

    # Optional logging
    [string]$LogPath
  )

  if (-not (Get-Command Get-ADTrust -ErrorAction SilentlyContinue)) {
    $msg = "ActiveDirectory module missing Get-ADTrust. Skipping trusts inventory."
    if ($LogPath) { Write-LcLog -Path $LogPath -Level WARN -Message $msg }
    return @()
  }

  # Prefer a forest context if supplied; otherwise trusts are typically queried per-domain.
  # We'll attempt in current context if no identity is specified.
  $params = @{}
  if ($ForestName) { $params['Server'] = $ForestName }
  if ($Server)     { $params['Server'] = $Server }

  try {
    $trusts = Get-ADTrust -Filter * @params -ErrorAction Stop
  } catch {
    $msg = "Failed to enumerate trusts (may be permissions or query scope). $($_.Exception.Message)"
    if ($LogPath) { Write-LcLog -Path $LogPath -Level WARN -Message $msg }
    return @()
  }

  $rows = foreach ($t in $trusts) {
    [pscustomobject]@{
      Name               = [string]$t.Name
      Source             = [string]$t.Source
      Target             = [string]$t.Target
      Direction          = [string]$t.Direction
      TrustType          = [string]$t.TrustType
      TrustAttributes    = [string]$t.TrustAttributes
      ForestTransitive   = $t.ForestTransitive
      SelectiveAuthentication = $t.SelectiveAuthentication
      SIDFilteringForestAware = $t.SIDFilteringForestAware
      SIDFilteringQuarantined = $t.SIDFilteringQuarantined
      UsesAESKeys        = $t.UsesAESKeys
      UsesRC4Encryption  = $t.UsesRC4Encryption
    }
  }

  return @($rows)
}
