function Get-LcAdFineGrainedPasswordPolicyAssignments {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object]$DomainContext,

    [string]$LogPath
  )

  if (-not (Get-Command Get-ADFineGrainedPasswordPolicy -ErrorAction SilentlyContinue)) {
    if ($LogPath) { Write-LcLog -Path $LogPath -Level WARN -Message "FGPP cmdlets not available; skipping FGPP assignments." }
    return @()
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $pols = @()
  try {
    $pols = @(Get-ADFineGrainedPasswordPolicy -Filter * -Server $server -ErrorAction Stop)
  } catch {
    if ($LogPath) { Write-LcLog -Path $LogPath -Level WARN -Message ("Failed to enumerate FGPP assignments for {0}. {1}" -f $domain, $_.Exception.Message) }
    return @()
  }

  $rows = New-Object System.Collections.Generic.List[object]

  foreach ($p in $pols) {
    $appliesTo = @($p.AppliesTo)
    if (-not $appliesTo -or $appliesTo.Count -eq 0) { continue }

    foreach ($dn in $appliesTo) {
      if ([string]::IsNullOrWhiteSpace([string]$dn)) { continue }

      $rows.Add([pscustomobject]@{
        DomainFqdn        = $domain
        PolicyName        = [string]$p.Name
        PolicyDN          = [string]$p.DistinguishedName
        Precedence        = $p.Precedence
        AppliesToDN       = [string]$dn
      })
    }
  }

  return @($rows)
}
