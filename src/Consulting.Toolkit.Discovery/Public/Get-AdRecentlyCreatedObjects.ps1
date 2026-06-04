function Get-AdRecentlyCreatedObjects {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    [Parameter()]
    [ValidateRange(1,3650)]
    [int]$Days = 10,

    [Parameter()]
    [switch]$IncludeGpo,

    [Parameter()]
    [string]$LogPath
  )

  if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADObject missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = if ($DomainContext.Server) { [string]$DomainContext.Server } else { [string]$DomainContext.DomainController }
  $searchBase = [string]$DomainContext.DomainDn
  $cutoff = (Get-Date).AddDays(-1 * $Days)
  $cutoffLdap = $cutoff.ToUniversalTime().ToString('yyyyMMddHHmmss.0Z')

  $rows = New-Object System.Collections.Generic.List[object]
  $seenDn = @{}

  function Add-RecentRow {
    param(
      [Parameter(Mandatory)] $Obj,
      [Parameter(Mandatory)] [string]$ObjectClass,
      [string]$NameOverride = $null
    )
    $dn = [string]$Obj.DistinguishedName
    if ([string]::IsNullOrWhiteSpace($dn)) { return }
    if ($seenDn.ContainsKey($dn)) { return }
    $seenDn[$dn] = $true

    $rows.Add([pscustomobject]@{
      DomainFqdn         = $domain
      ObjectClass        = $ObjectClass
      Name               = if ($NameOverride) { $NameOverride } else { [string]$Obj.Name }
      SamAccountName     = [string]$Obj.SamAccountName
      DistinguishedName  = $dn
      ObjectGuid         = [string]$Obj.ObjectGuid
      WhenCreated        = $Obj.whenCreated
      LookbackDays       = $Days
    })
  }

  $counts = @{
    user     = 0
    group    = 0
    computer = 0
    gpo      = 0
  }

  try {
    $users = @(
      Get-ADUser -LDAPFilter "(whenCreated>=$cutoffLdap)" -SearchBase $searchBase -SearchScope Subtree -Server $server `
        -Properties whenCreated,objectGuid,samAccountName,distinguishedName,name -ResultPageSize 1000 -ErrorAction Stop
    )
    foreach ($u in $users) { Add-RecentRow -Obj $u -ObjectClass 'user' }
    $counts.user = $users.Count
  } catch {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Recently created users query failed for {0} on {1}. {2}" -f $domain, $server, $_.Exception.Message) }
  }

  try {
    $groups = @(
      Get-ADGroup -LDAPFilter "(whenCreated>=$cutoffLdap)" -SearchBase $searchBase -SearchScope Subtree -Server $server `
        -Properties whenCreated,objectGuid,samAccountName,distinguishedName,name,objectSid -ResultPageSize 1000 -ErrorAction Stop
    )
    $groups = @($groups | Where-Object { -not (Test-AdBuiltInGroup -Group $_) })
    foreach ($g in $groups) { Add-RecentRow -Obj $g -ObjectClass 'group' }
    $counts.group = $groups.Count
  } catch {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Recently created groups query failed for {0} on {1}. {2}" -f $domain, $server, $_.Exception.Message) }
  }

  try {
    $computers = @(
      Get-ADComputer -LDAPFilter "(whenCreated>=$cutoffLdap)" -SearchBase $searchBase -SearchScope Subtree -Server $server `
        -Properties whenCreated,objectGuid,samAccountName,distinguishedName,name -ResultPageSize 1000 -ErrorAction Stop
    )
    foreach ($c in $computers) { Add-RecentRow -Obj $c -ObjectClass 'computer' }
    $counts.computer = $computers.Count
  } catch {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Recently created computers query failed for {0} on {1}. {2}" -f $domain, $server, $_.Exception.Message) }
  }

  if ($IncludeGpo) {
    try {
      $gpoBase = "CN=Policies,CN=System,$searchBase"
      $gpos = @(
        Get-ADObject -LDAPFilter "(&(objectClass=groupPolicyContainer)(whenCreated>=$cutoffLdap))" `
          -SearchBase $gpoBase -SearchScope OneLevel -Server $server `
          -Properties whenCreated,objectGuid,samAccountName,distinguishedName,displayName,name -ResultPageSize 1000 -ErrorAction Stop
      )
      foreach ($gpo in $gpos) {
        $gpoName = if ($gpo.displayName) { [string]$gpo.displayName } else { [string]$gpo.Name }
        Add-RecentRow -Obj $gpo -ObjectClass 'gpo' -NameOverride $gpoName
      }
      $counts.gpo = $gpos.Count
    } catch {
      if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Recently created GPO query failed for {0} on {1}. {2}" -f $domain, $server, $_.Exception.Message) }
    }
  }

  if ($LogPath) {
    Write-AdLog -Path $LogPath -Level INFO -Message ("Recently created objects for {0} on {1} (lookback={2}d): users={3}, groups={4}, computers={5}, gpos={6}, totalRows={7}" -f `
        $domain, $server, $Days, $counts.user, $counts.group, $counts.computer, $counts.gpo, $rows.Count)
  }

  return @($rows.ToArray())
}
