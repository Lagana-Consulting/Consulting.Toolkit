function Get-AdWritableDc {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainFqdn,

    [ValidateRange(1,60000)][int]$TimeoutMs = 1500,

    # Total budget for connectivity probes; AD enumeration has its native timeout.
    [ValidateRange(1,60000)][int]$ProbeBudgetMs = 10000
  )

  if (-not (Get-Command Get-ADDomainController -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  # Try to prefer a writable DC, then fall back.
  $candidates = @()

  try {
    $candidates = @(Get-ADDomainController -Filter * -Server $DomainFqdn -ErrorAction Stop |
      Where-Object { -not ($_.PSObject.Properties['IsReadOnly'] -and $_.IsReadOnly) } |
      Sort-Object -Property IsPdc, IsGlobalCatalog -Descending)
  }
  catch {
    Write-AdDiscoveryEvent -Kind Query -Operation 'DC Selection' -Status RETRY -ErrorRecord $_ -Details @{ NextTarget = $DomainFqdn }
    # If we can't enumerate DCs (network issue), just use domain as fallback
    # The subsequent Get-ADDomain or other cmdlets may still work if called locally
    return $DomainFqdn
  }

  $probeTimer = [System.Diagnostics.Stopwatch]::StartNew()
  foreach ($dc in $candidates) {
    $hostName = $dc.HostName
    if (-not $hostName) { continue }

    $remainingMs = $ProbeBudgetMs - [int]$probeTimer.ElapsedMilliseconds
    if ($remainingMs -le 0) {
      Write-AdDiscoveryEvent -Kind Query -Operation 'DC Reachability' -Status INFO -Details @{ ProbeBudgetMs = $ProbeBudgetMs; Reason = 'Probe budget exhausted'; NextTarget = $DomainFqdn }
      break
    }

    # AD cmdlets use ADWS; LDAP alone does not establish its availability.
    try {
      $attemptTimeoutMs = [math]::Min($TimeoutMs, $remainingMs)
      $ok = Test-AdTcpPort -ComputerName $hostName -Port 9389 -TimeoutMs $attemptTimeoutMs
      Write-AdDiscoveryEvent -Kind Query -Operation 'DC Reachability' -Status INFO -Details @{ Server = $hostName; Port = 9389; Reachable = [bool]$ok; TimeoutMs = $attemptTimeoutMs; ProbeBudgetMs = $ProbeBudgetMs }
      if ($ok) { return $hostName }
    }
    catch {
      Write-AdDiscoveryEvent -Kind Query -Operation 'DC Reachability' -Status RETRY -ErrorRecord $_ -Details @{ Server = $hostName; NextTarget = 'Next DC candidate' }
      # ignore and continue
    }
  }

  # Last resort: just return domain itself (lets AD cmdlets choose)
  return $DomainFqdn
}
