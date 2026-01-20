function Get-LcPrivilegedAccounts {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object]$DomainContext
  )

  if (-not (Get-Command Get-ADGroup -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADGroup missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $privGroupNames = Get-LcPrivilegedGroupNames

  # Resolve group DNs that exist in this domain
  $groups = New-Object System.Collections.Generic.List[object]
  foreach ($gn in $privGroupNames) {
    try {
      $g = Get-ADGroup -Identity $gn -Server $server -ErrorAction Stop
      $groups.Add($g)
    } catch {
      # group not found in domain, skip
    }
  }

  $bySam = @{}

  # 1) From privileged groups (recursive)
  foreach ($g in $groups) {
    $members = Get-LcGroupMembersRecursive -GroupDn $g.DistinguishedName -Server $server
    foreach ($m in $members) {
      $sam = [string]$m.SamAccountName
      if (-not $bySam.ContainsKey($sam)) {
        $bySam[$sam] = [pscustomobject]@{
          DomainFqdn        = $domain
          SamAccountName    = $sam
          DistinguishedName = [string]$m.DistinguishedName
          InPrivGroups      = $true
          PrivGroups        = New-Object System.Collections.Generic.List[string]
          AdminCount        = $false
        }
      }
      $bySam[$sam].PrivGroups.Add([string]$g.Name)
    }
  }

  # 2) adminCount=1 users
  $adminUsers = @()
  try {
    $adminUsers = @(Get-ADUser -LDAPFilter '(adminCount=1)' -Server $server -Properties adminCount -ErrorAction Stop)
  } catch {
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
        PrivGroups        = New-Object System.Collections.Generic.List[string]
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
