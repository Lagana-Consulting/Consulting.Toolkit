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

  $groups = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADGroup' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
    param($queryServer)
    $queryParams = @{ Filter = '*'; SearchBase = $DomainContext.DomainDn; SearchScope = 'Subtree'; ErrorAction = 'Stop' }
    $queryParams.Properties = @('mail', 'groupCategory', 'groupScope', 'whenCreated', 'whenChanged', 'description', 'objectSid')
    if ($queryServer) { $queryParams.Server = $queryServer }
    Get-ADGroup @queryParams | Sort-Object Name
  })

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
