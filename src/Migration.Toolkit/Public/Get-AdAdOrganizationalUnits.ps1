function Get-AdAdOrganizationalUnits {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADOrganizationalUnit -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADOrganizationalUnit missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server
  $baseDn = [string]$DomainContext.DomainDn

  $ous = @()
  try {
    $ous = @(Get-ADOrganizationalUnit -Filter * -SearchBase $baseDn -SearchScope Subtree -Server $server -Properties whenCreated, whenChanged, description -ErrorAction Stop |
      Sort-Object DistinguishedName)
  } catch {
    throw "Failed to enumerate OUs for $domain via $server. $($_.Exception.Message)"
  }

  foreach ($ou in $ous) {
    $dn = [string]$ou.DistinguishedName

    # OU depth: count OU= components
    $ouLevel = ([regex]::Matches($dn, 'OU=')).Count
    $isTop = ($ouLevel -eq 1)

    [pscustomobject]@{
      DomainFqdn        = $domain
      Name              = [string]$ou.Name
      DistinguishedName = $dn
      Description       = [string]$ou.Description
      WhenCreated       = $ou.whenCreated
      WhenChanged       = $ou.whenChanged
      Level             = $ouLevel
      IsTopLevel        = $isTop
    }
  }
}
