function Get-AdGpoDelegation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    [string]$LogPath
  )

  $domain = [string]$DomainContext.DomainFqdn
  $server = if ($DomainContext.Server) { [string]$DomainContext.Server } else { [string]$DomainContext.DomainController }

  if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {
    Stop-AdDiscoveryCollection -Message 'GroupPolicy module not available; GPO delegation was not collected.'
  }
  if (-not (Get-Command Get-GPPermission -ErrorAction SilentlyContinue)) {
    Stop-AdDiscoveryCollection -Message 'Get-GPPermission is unavailable; GPO delegation was not collected.'
  }

  $gpos = @()
  try {
    $gpos = @(Get-GPO -All -Domain $domain -Server $server -ErrorAction Stop)
  } catch {
    throw
  }

  $rows = @()
  $failed = 0
  $getGPPermissionCmd = Get-Command Get-GPPermission -ErrorAction SilentlyContinue
  $supportsServer = $false
  if ($getGPPermissionCmd -and $getGPPermissionCmd.Parameters.ContainsKey('Server')) {
    $supportsServer = $true
  }

  function New-GpoDelegationRow {
    param(
      [Parameter(Mandatory)] $Gpo,
      [Parameter(Mandatory)] $Permission,
      [Parameter(Mandatory)] [string]$DomainName
    )

    $trusteeName = $null
    $trusteeType = $null

    if ($Permission.PSObject.Properties.Name -contains 'Trustee') {
      $trustee = $Permission.Trustee
      if ($trustee -is [string]) {
        $trusteeName = [string]$trustee
      } elseif ($trustee) {
        if ($trustee.PSObject.Properties.Name -contains 'Name') { $trusteeName = [string]$trustee.Name }
        if ($trustee.PSObject.Properties.Name -contains 'TrusteeType') { $trusteeType = [string]$trustee.TrusteeType }
        if (-not $trusteeType -and $trustee.PSObject.Properties.Name -contains 'SidType') { $trusteeType = [string]$trustee.SidType }
      }
    }

    if (-not $trusteeName -and ($Permission.PSObject.Properties.Name -contains 'TrusteeName')) {
      $trusteeName = [string]$Permission.TrusteeName
    }
    if (-not $trusteeType -and ($Permission.PSObject.Properties.Name -contains 'TrusteeType')) {
      $trusteeType = [string]$Permission.TrusteeType
    }

    [pscustomobject]@{
      DomainFqdn     = $DomainName
      GpoDisplayName = [string]$Gpo.DisplayName
      GpoId          = [string]$Gpo.Id
      Trustee        = $trusteeName
      TrusteeType    = $trusteeType
      Permission     = [string]$Permission.Permission
      Inherited      = if ($Permission.PSObject.Properties.Name -contains 'Inherited') { [bool]$Permission.Inherited } else { $null }
    }
  }

  foreach ($g in $gpos) {
    try {
      $permParams = @{
        Guid        = $g.Id
        Domain      = $domain
        All         = $true
        ErrorAction = 'Stop'
      }
      if ($supportsServer) { $permParams['Server'] = $server }

      $perms = @(Get-GPPermission @permParams)
      foreach ($p in $perms) {
        $rows += New-GpoDelegationRow -Gpo $g -Permission $p -DomainName $domain
      }
    } catch {
      Write-AdDiscoveryEvent -Kind Query -Status RETRY -ErrorRecord $_ -Details @{ Gpo = [string]$g.Id; NextLookup = 'DisplayName' }
      # Fallback for environments where -Guid can fail unexpectedly.
      try {
        $permParams = @{
          Name        = [string]$g.DisplayName
          Domain      = $domain
          All         = $true
          ErrorAction = 'Stop'
        }
        if ($supportsServer) { $permParams['Server'] = $server }

        $perms = @(Get-GPPermission @permParams)
        foreach ($p in $perms) {
          $rows += New-GpoDelegationRow -Gpo $g -Permission $p -DomainName $domain
        }
      } catch {
        Write-AdDiscoveryCollectionIssue -ErrorRecord $_ -Details @{ Gpo = [string]$g.Id }
        $failed++
        if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Failed GPPermission for {0}. {1}" -f $g.DisplayName, $_.Exception.Message) }
      }
    }
  }

  if ($LogPath -and $gpos.Count -gt 0 -and $rows.Count -eq 0) {
    Write-AdLog -Path $LogPath -Level WARN -Message ("GPO delegation returned no rows for {0}. GPOs={1}, permission query failures={2}. Check account rights and GroupPolicy remoting/DC access." -f $domain, $gpos.Count, $failed)
  }

  return $rows
}
