function Get-LcGpoInventory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    $DomainContext,

    [string]$LogPath
  )

  if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {
    if ($LogPath) { Write-LcLog -Path $LogPath -Level WARN -Message "GroupPolicy module not available; skipping GPO inventory." }
    return @()
  }

  $domain = [string]$DomainContext.DomainFqdn

  $gpos = @()
  try {
    $gpos = @(Get-GPO -All -Domain $domain -ErrorAction Stop | Sort-Object DisplayName)
  } catch {
    if ($LogPath) { Write-LcLog -Path $LogPath -Level WARN -Message ("Failed to enumerate GPOs for {0}. {1}" -f $domain, $_.Exception.Message) }
    return @()
  }

  foreach ($g in $gpos) {
    [pscustomobject]@{
      DomainFqdn     = $domain
      DisplayName    = [string]$g.DisplayName
      Id             = [string]$g.Id
      Owner          = [string]$g.Owner
      CreationTime   = $g.CreationTime
      ModificationTime = $g.ModificationTime
      GpoStatus      = [string]$g.GpoStatus
      Description    = [string]$g.Description
      UserVersion    = [string]$g.UserVersion
      ComputerVersion= [string]$g.ComputerVersion
      WmiFilter      = [string]$g.WmiFilter
    }
  }
}
