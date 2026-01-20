function Get-LcWritableDc {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainFqdn,

    [int]$TimeoutMs = 1500
  )

  if (-not (Get-Command Get-ADDomainController -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  # Try to prefer a writable DC, then fall back.
  $candidates = @()

  try {
    $candidates = @(Get-ADDomainController -Filter * -Server $DomainFqdn -ErrorAction Stop |
      Sort-Object -Property IsPdc,IsGlobalCatalog -Descending)
  } catch {
    throw "Failed to enumerate domain controllers for $DomainFqdn. $($_.Exception.Message)"
  }

  foreach ($dc in $candidates) {
    $hostName = $dc.HostName
    if (-not $hostName) { continue }

    # Quick reachability check (no ICMP requirement)
    try {
      $ok = Test-NetConnection -ComputerName $hostName -Port 389 -InformationLevel Quiet -WarningAction SilentlyContinue
      if ($ok) { return $hostName }
    } catch {
      # ignore and continue
    }
  }

  # Last resort: just return domain itself (lets AD cmdlets choose)
  return $DomainFqdn
}
