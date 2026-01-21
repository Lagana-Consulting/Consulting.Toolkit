function Get-LcAdGroups {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADGroup -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADGroup missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $groups = @()
  try {
    $groups = @(Get-ADGroup -Filter * -Server $server -Properties mail, groupCategory, groupScope, whenCreated, whenChanged, description -ErrorAction Stop |
      Sort-Object Name)
  } catch {
    throw "Failed to enumerate groups for $domain via $server. $($_.Exception.Message)"
  }

  foreach ($g in $groups) {
    [pscustomobject]@{
      DomainFqdn        = $domain
      Name              = [string]$g.Name
      SamAccountName    = [string]$g.SamAccountName
      DistinguishedName = [string]$g.DistinguishedName
      GroupCategory     = [string]$g.GroupCategory
      GroupScope        = [string]$g.GroupScope
      Mail              = [string]$g.mail
      WhenCreated       = $g.whenCreated
      WhenChanged       = $g.whenChanged
      Description       = [string]$g.description
    }
  }
}
