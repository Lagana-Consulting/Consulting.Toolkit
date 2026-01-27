function Get-AdAdDomainContext {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainFqdn,

    # Optional: if you already chose a DC, pass it
    [string]$Server,

    # Optional: log path
    [string]$LogPath
  )

  if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools / Import-Module ActiveDirectory."
  }

  $domain = $DomainFqdn.Trim().ToLowerInvariant()

  # Pick a server/DC if not provided
  $dc = $Server
  if ([string]::IsNullOrWhiteSpace($dc)) {
    $dc = Get-AdWritableDc -DomainFqdn $domain
  }

  if ($LogPath) {
    Write-AdLog -Path $LogPath -Level INFO -Message ("Domain context: Domain={0} Server/DC={1}" -f $domain, $dc)
  }

  # Query domain object
  $dobj = $null
  try {
    $dobj = Get-ADDomain -Identity $domain -Server $dc -ErrorAction Stop
  } catch {
    throw "Failed to query domain '$domain' using server '$dc'. $($_.Exception.Message)"
  }

  # Build a reusable context object
  [pscustomobject]@{
    DomainFqdn      = $domain
    Server          = $dc
    DomainDn        = [string]$dobj.DistinguishedName
    NetBiosName     = [string]$dobj.NetBIOSName
    DomainMode      = [string]$dobj.DomainMode
    PdcEmulator     = [string]$dobj.PDCEmulator
    RidMaster       = [string]$dobj.RIDMaster
    InfrastructureMaster = [string]$dobj.InfrastructureMaster
    Forest          = [string]$dobj.Forest
    DnsRoot         = [string]$dobj.DNSRoot
  }
}
