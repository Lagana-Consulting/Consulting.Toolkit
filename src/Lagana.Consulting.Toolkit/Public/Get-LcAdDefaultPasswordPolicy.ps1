function Get-LcAdDefaultPasswordPolicy {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object]$DomainContext
  )

  if (-not (Get-Command Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADDefaultDomainPasswordPolicy missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $pol = $null
  try {
    $pol = Get-ADDefaultDomainPasswordPolicy -Server $server -ErrorAction Stop
  } catch {
    throw "Failed to get default domain password policy for $domain via $server. $($_.Exception.Message)"
  }

  [pscustomobject]@{
    DomainFqdn                 = $domain
    ComplexityEnabled          = [bool]$pol.ComplexityEnabled
    MinPasswordLength          = $pol.MinPasswordLength
    PasswordHistoryCount       = $pol.PasswordHistoryCount
    MinPasswordAgeDays         = [math]::Round($pol.MinPasswordAge.TotalDays, 2)
    MaxPasswordAgeDays         = [math]::Round($pol.MaxPasswordAge.TotalDays, 2)
    LockoutThreshold           = $pol.LockoutThreshold
    LockoutDurationMinutes     = [math]::Round($pol.LockoutDuration.TotalMinutes, 2)
    LockoutObservationWindowMinutes = [math]::Round($pol.LockoutObservationWindow.TotalMinutes, 2)
    ReversibleEncryptionEnabled= [bool]$pol.ReversibleEncryptionEnabled
  }
}
