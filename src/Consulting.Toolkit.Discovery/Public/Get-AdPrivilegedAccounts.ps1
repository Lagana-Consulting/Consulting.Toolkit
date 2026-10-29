function Get-AdPrivilegedAccounts {
  <#
  .SYNOPSIS
  Identifies privileged accounts in a domain.

  .DESCRIPTION
  Discovers accounts with elevated privileges through:
  1. Membership in privileged groups (recursive enumeration):
     - Enterprise Admins, Schema Admins, Domain Admins
     - Administrators, Server Operators, Backup Operators, etc.
  2. adminCount=1 attribute (historically protected accounts)

  Results include all accounts meeting either criterion with detail on
  which privileged groups they belong to.

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext. Required.

  .EXAMPLE
  $ctx = Get-AdAdDomainContext -DomainFqdn "contoso.com"
  $privAccounts = Get-AdPrivilegedAccounts -DomainContext $ctx

  Discovers all privileged accounts in contoso.com.

  .EXAMPLE
  $privAccounts | Where-Object InPrivGroups |
    Select-Object SamAccountName, @{N='Groups';E={$_.PrivGroups -join ';'}}

  Shows accounts with their privileged group memberships.

  .EXAMPLE
  $adminCountOnly = $privAccounts | Where-Object { $_.AdminCount -and -not $_.InPrivGroups }

  Finds orphaned privileged accounts (adminCount=1 but not in current priv groups).

  .OUTPUTS
  PSCustomObject[] with properties:
  - DomainFqdn, SamAccountName, DistinguishedName
  - InPrivGroups (boolean)
  - PrivGroups (array of privileged group names)
  - AdminCount (boolean)

  .NOTES
  Requires Active Directory PowerShell module.
  Group membership is recursively expanded (includes nested memberships).
  AdminCount=1 indicates historical administrative protection (may not reflect current state).
  Use for:
  - Security audit and compliance
  - Migration planning (privileged accounts need special handling)
  - Access review

  .LINK
  Get-AdAdDomainContext
  Get-AdPrivilegedGroupNames
  Get-AdGroupMembersRecursive
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

  $privGroupNames = Get-AdPrivilegedGroupNames

  # Resolve group DNs that exist in this domain
  $groups = @()
  foreach ($gn in $privGroupNames) {
    try {
      $g = Get-ADGroup -Identity $gn -Server $server -ErrorAction Stop
      $groups += $g
    } catch {
      if (Test-AdDiscoveryIdentityNotFound -ErrorRecord $_) {
        Write-AdDiscoveryEvent -Status INFO -Message "Privileged group is not present in this domain: $gn"
      } else {
        Write-AdDiscoveryCollectionIssue -ErrorRecord $_ -Details @{ Group = $gn }
      }
    }
  }

  $bySam = @{}

  # 1) From privileged groups (recursive)
  foreach ($g in $groups) {
    $members = Get-AdGroupMembersRecursive -GroupDn $g.DistinguishedName -Server $server
    foreach ($m in $members) {
      $sam = [string]$m.SamAccountName
      if (-not $bySam.ContainsKey($sam)) {
        $bySam[$sam] = [pscustomobject]@{
          DomainFqdn        = $domain
          SamAccountName    = $sam
          DistinguishedName = [string]$m.DistinguishedName
          InPrivGroups      = $true
          PrivGroups        = @()
          AdminCount        = $false
        }
      }
      $bySam[$sam].PrivGroups += [string]$g.Name
    }
  }

  # 2) adminCount=1 users
  $adminUsers = @()
  try {
    $adminUsers = @(Get-ADUser -LDAPFilter '(adminCount=1)' -SearchBase $DomainContext.DomainDn -SearchScope Subtree -Server $server -Properties adminCount -ErrorAction Stop)
  } catch {
    Write-AdDiscoveryCollectionIssue -ErrorRecord $_ -Message 'The adminCount user query failed; privileged account coverage is incomplete.'
    $adminUsers = @()
  }

  foreach ($u in $adminUsers) {
    $sam = [string]$u.SamAccountName
    if (-not $bySam.ContainsKey($sam)) {
      $bySam[$sam] = [pscustomobject]@{
        DomainFqdn        = $domain
        SamAccountName    = $sam
        DistinguishedName = [string]$u.DistinguishedName
        InPrivGroups      = $false
        PrivGroups        = @()
        AdminCount        = $true
      }
    } else {
      $bySam[$sam].AdminCount = $true
    }
  }

  # Emit rows
  foreach ($k in $bySam.Keys | Sort-Object) {
    $row = $bySam[$k]
    [pscustomobject]@{
      DomainFqdn        = $row.DomainFqdn
      SamAccountName    = $row.SamAccountName
      DistinguishedName = $row.DistinguishedName
      InPrivGroups      = [bool]$row.InPrivGroups
      PrivGroups        = (($row.PrivGroups | Sort-Object -Unique) -join ';')
      AdminCount        = [bool]$row.AdminCount
    }
  }
}
