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
    Stop-AdDiscoveryCollection -Message 'GroupPolicy module not available; GPO inventory was not collected.'
  }

  $domain = [string]$DomainContext.DomainFqdn

  $gpos = @()
  try {
    Write-AdDiscoveryEvent -Kind Query -Status START -Details @{ Command = 'Get-GPO'; Domain = $domain; Server = $DomainContext.Server }
    $gpos = @(Get-GPO -All -Domain $domain -Server $DomainContext.Server -ErrorAction Stop | Sort-Object DisplayName)
    Write-AdDiscoveryEvent -Kind Query -Status OK -RowCount $gpos.Count -Details @{ Command = 'Get-GPO'; Server = $DomainContext.Server }
  } catch {
    throw
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
      UserVersion      = Get-AdGpoVersionNumber -Gpo $g -Section User
      ComputerVersion  = Get-AdGpoVersionNumber -Gpo $g -Section Computer
      WmiFilter        = if ($g.PSObject.Properties['WmiFilter'] -and $g.WmiFilter) { if ($g.WmiFilter.PSObject.Properties['Name']) { [string]$g.WmiFilter.Name } else { [string]$g.WmiFilter } } else { $null }
      GpoId            = [string]$g.Id
    }
  }
}
