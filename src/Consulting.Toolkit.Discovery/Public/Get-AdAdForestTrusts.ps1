function Get-AdAdForestTrusts {
  [CmdletBinding()]
  param(
    [string]$ForestName,
    [string]$Server,

    # Optional logging
    [string]$LogPath
  )

  if (-not (Get-Command Get-ADTrust -ErrorAction SilentlyContinue)) {
    $msg = "ActiveDirectory module missing Get-ADTrust. Skipping trusts inventory."
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message $msg }
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
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message $msg }
    return @()
  }

  $rows = foreach ($t in $trusts) {
    $sidFilteringStatus = if ($t.SIDFilteringQuarantined -eq $true) {
      'Quarantined'
    } elseif ($t.SIDFilteringForestAware -eq $true) {
      'ForestAware'
    } elseif ($t.SIDFilteringForestAware -eq $false -or $t.SIDFilteringQuarantined -eq $false) {
      'DisabledOrUnknown'
    } else {
      'Unknown'
    }

    [pscustomobject]@{
      Name                     = [string]$t.Name
      Source                   = [string]$t.Source
      Target                   = [string]$t.Target
      Direction                = [string]$t.Direction
      TrustType                = [string]$t.TrustType
      TrustAttributes          = [string]$t.TrustAttributes
      ForestTransitive         = [bool]$t.ForestTransitive
      SelectiveAuthentication  = [bool]$t.SelectiveAuthentication
      SIDFilteringForestAware  = if ($null -ne $t.SIDFilteringForestAware) { [bool]$t.SIDFilteringForestAware } else { $null }
      SIDFilteringQuarantined  = if ($null -ne $t.SIDFilteringQuarantined) { [bool]$t.SIDFilteringQuarantined } else { $null }
      SIDFilteringStatus       = $sidFilteringStatus
      UsesAESKeys              = if ($null -ne $t.UsesAESKeys) { [bool]$t.UsesAESKeys } else { $null }
      UsesRC4Encryption        = if ($null -ne $t.UsesRC4Encryption) { [bool]$t.UsesRC4Encryption } else { $null }
    }
  }

  return @($rows)
}
