function Get-AdAdDefaultPasswordPolicy {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    $DomainContext
  )

  if (-not (Get-Command Get-ADDefaultDomainPasswordPolicy -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADDefaultDomainPasswordPolicy missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $pol = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADDefaultDomainPasswordPolicy' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
      param($queryServer)
      Get-ADDefaultDomainPasswordPolicy -Identity $domain -Server $queryServer -ErrorAction Stop
  })
  $pol = $pol | Select-Object -First 1

  [pscustomobject]@{
    DomainFqdn                      = $domain
    ComplexityEnabled               = [bool]$pol.ComplexityEnabled
    MinPasswordLength               = $pol.MinPasswordLength
    PasswordHistoryCount            = $pol.PasswordHistoryCount
    MinPasswordAgeDays              = [math]::Round($pol.MinPasswordAge.TotalDays, 2)
    MaxPasswordAgeDays              = [math]::Round($pol.MaxPasswordAge.TotalDays, 2)
    LockoutThreshold                = $pol.LockoutThreshold
    LockoutDurationMinutes          = [math]::Round($pol.LockoutDuration.TotalMinutes, 2)
    LockoutObservationWindowMinutes = [math]::Round($pol.LockoutObservationWindow.TotalMinutes, 2)
    ReversibleEncryptionEnabled     = [bool]$pol.ReversibleEncryptionEnabled
  }
}
