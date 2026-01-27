function Get-AdGpoInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    [string]$LogPath
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message "GroupPolicy module not available; skipping GPO inventory." }
    return @()
  }

  $domain = [string]$DomainContext.DomainFqdn

  $gpos = @()
  try {
    $gpos = @(Get-GPO -All -Domain $domain -ErrorAction Stop | Sort-Object DisplayName)
  } catch {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Failed to enumerate GPOs for {0}. {1}" -f $domain, $_.Exception.Message) }
    return @()
  }

  foreach ($g in $gpos) {
    [pscustomobject]@{
      DomainFqdn       = $domain
      DisplayName      = [string]$g.DisplayName
      Id               = [string]$g.Id
      Owner            = [string]$g.Owner
      CreationTime     = $g.CreationTime
      ModificationTime = $g.ModificationTime
      GpoStatus        = [string]$g.GpoStatus
      Description      = [string]$g.Description
      UserVersion      = if ($g.PSObject.Properties['UserVersion']) { [string]$g.UserVersion } else { $null }
      ComputerVersion  = if ($g.PSObject.Properties['ComputerVersion']) { [string]$g.ComputerVersion } else { $null }
      WmiFilter        = if ($g.PSObject.Properties['WmiFilter']) { [string]$g.WmiFilter } else { $null }
    }
  }
}
