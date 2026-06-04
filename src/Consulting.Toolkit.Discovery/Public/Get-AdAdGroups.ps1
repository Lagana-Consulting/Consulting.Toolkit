function Get-AdAdGroups {
  <#
  .SYNOPSIS
  Retrieves all groups from a domain.

  .DESCRIPTION
  Enumerates all security and distribution groups with key properties:
  - Group type (security vs. distribution)
  - Scope (domain local, global, universal)
  - Mail attribute for mail-enabled groups
  - Creation and modification timestamps

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext. Required.

  .EXAMPLE
  $ctx = Get-AdAdDomainContext -DomainFqdn "contoso.com"
  $groups = Get-AdAdGroups -DomainContext $ctx

  Gets all groups in contoso.com domain.

  .EXAMPLE
  $groups | Where-Object { $_.GroupCategory -eq 'Security' -and $_.GroupScope -eq 'Universal' }

  Filters to universal security groups.

  .EXAMPLE
  $groups | Where-Object Mail | Select-Object Name, Mail, GroupCategory

  Shows mail-enabled groups with email addresses.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  PSCustomObject[]. Group objects with properties:
  - DomainFqdn, Name, SamAccountName, DistinguishedName
  - GroupCategory (Security/Distribution), GroupScope (DomainLocal/Global/Universal)
  - Mail, WhenCreated, WhenChanged, Description

  .NOTES
  Requires Active Directory PowerShell module.
  Results are sorted by Name.

  .LINK
  Get-AdAdDomainContext
  Get-ADGroup
  #>
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
    $groups = @(Get-ADGroup -Filter * -Server $server -Properties mail, groupCategory, groupScope, whenCreated, whenChanged, description, objectSid -ErrorAction Stop |
      Sort-Object Name)
  } catch {
    # Try without server parameter as fallback
    try {
      $groups = @(Get-ADGroup -Filter * -Properties mail, groupCategory, groupScope, whenCreated, whenChanged, description, objectSid -ErrorAction Stop |
        Sort-Object Name)
    } catch {
      throw "Failed to enumerate groups for $domain. $($_.Exception.Message)"
    }
  }

  foreach ($g in @($groups | Where-Object { -not (Test-AdBuiltInGroup -Group $_) })) {
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
