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
    Stop-AdDiscoveryCollection -Message 'FGPP cmdlets not available; fine-grained password policies were not collected.'
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server

  $pols = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADFineGrainedPasswordPolicy' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
    param($queryServer)
    $queryParams = @{ Filter = '*'; SearchBase = $DomainContext.DomainDn; SearchScope = 'Subtree'; ErrorAction = 'Stop' }
    if ($queryServer) { $queryParams.Server = $queryServer }
    Get-ADFineGrainedPasswordPolicy @queryParams | Sort-Object Name
  })

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
