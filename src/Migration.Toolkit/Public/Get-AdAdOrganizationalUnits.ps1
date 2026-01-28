function Get-AdAdOrganizationalUnits {
  <#
  .SYNOPSIS
  Retrieves all organizational units from a domain.

  .DESCRIPTION
  Enumerates all OUs with properties including:
  - Distinguished name and nesting level
  - Creation and modification timestamps
  - Top-level OU detection
  Results are sorted by distinguished name.

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext. Required.

  .EXAMPLE
  $ctx = Get-AdAdDomainContext -DomainFqdn "contoso.com"
  $ous = Get-AdAdOrganizationalUnits -DomainContext $ctx

  Gets all OUs in contoso.com domain.

  .EXAMPLE
  $ous | Where-Object IsTopLevel | Select-Object Name, DistinguishedName

  Shows only top-level OUs (one level below domain root).

  .EXAMPLE
  $ous | Group-Object Level | Select-Object Count, Name

  Groups OUs by nesting depth to analyze hierarchy complexity.

  .EXAMPLE
  $deepOus = $ous | Where-Object { $_.Level -gt 5 }

  Finds deeply nested OUs (potential migration complexity indicator).

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  PSCustomObject[]. OU objects with properties:
  - DomainFqdn, Name, DistinguishedName, Description
  - WhenCreated, WhenChanged
  - Level (nesting depth), IsTopLevel (boolean)

  .NOTES
  Requires Active Directory PowerShell module.
  Level is calculated by counting OU= components in DN.
  Level 1 = top-level OU directly under domain root.

  .LINK
  Get-AdAdDomainContext
  Get-ADOrganizationalUnit
  #>
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
