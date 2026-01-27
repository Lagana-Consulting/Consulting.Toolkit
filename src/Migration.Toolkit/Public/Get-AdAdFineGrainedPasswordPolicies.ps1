function Get-AdAdFineGrainedPasswordPolicies {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    [string]$LogPath
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADFineGrainedPasswordPolicy -ErrorAction SilentlyContinue)) {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message "FGPP cmdlets not available; skipping fine-grained password policies." }
    return @()
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $pols = @()
  try {
    $pols = @(Get-ADFineGrainedPasswordPolicy -Filter * -Server $server -ErrorAction Stop | Sort-Object Name)
  } catch {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Failed to enumerate FGPP for {0}. {1}" -f $domain, $_.Exception.Message) }
    return @()
  }

  foreach ($p in $pols) {
    [pscustomobject]@{
      DomainFqdn                      = $domain
      Name                            = [string]$p.Name
      DistinguishedName               = [string]$p.DistinguishedName
      Precedence                      = $p.Precedence
      ComplexityEnabled               = [bool]$p.ComplexityEnabled
      MinPasswordLength               = $p.MinPasswordLength
      PasswordHistoryCount            = $p.PasswordHistoryCount
      MinPasswordAgeDays              = [math]::Round($p.MinPasswordAge.TotalDays, 2)
      MaxPasswordAgeDays              = [math]::Round($p.MaxPasswordAge.TotalDays, 2)
      LockoutThreshold                = $p.LockoutThreshold
      LockoutDurationMinutes          = [math]::Round($p.LockoutDuration.TotalMinutes, 2)
      LockoutObservationWindowMinutes = [math]::Round($p.LockoutObservationWindow.TotalMinutes, 2)
      ReversibleEncryptionEnabled     = [bool]$p.ReversibleEncryptionEnabled
      AppliesToCount                  = (@($p.AppliesTo) | Measure-Object).Count
    }
  }
}
