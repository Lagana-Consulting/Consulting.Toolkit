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

  # Validate both the requested domain object and the server's default naming
  # context. A root-domain DC is not a valid implicit target for child inventory.
  $selection = @{ Server = $dc }
  $dobj = Invoke-AdDiscoveryQuery -Operation 'Domain Context' -Server $dc -DomainFqdn $domain -RetryInDomain -Query {
    param($queryServer)
    $object = Get-ADDomain -Identity $domain -Server $queryServer -ErrorAction Stop
    $root = Get-ADRootDSE -Server $queryServer -ErrorAction Stop
    if ($object.DNSRoot -ne $domain -or $root.defaultNamingContext -ne $object.DistinguishedName) {
      throw "Server '$queryServer' does not provide the requested domain naming context '$domain'."
    }
    $selection.Server = $queryServer
    $object
  }
  $dc = $selection.Server

  # Build a reusable context object
  [pscustomobject]@{
    DomainFqdn           = $domain
    Server               = $dc
    DomainDn             = [string]$dobj.DistinguishedName
    NetBiosName          = [string]$dobj.NetBIOSName
    DomainMode           = [string]$dobj.DomainMode
    PdcEmulator          = [string]$dobj.PDCEmulator
    RidMaster            = [string]$dobj.RIDMaster
    InfrastructureMaster = [string]$dobj.InfrastructureMaster
    Forest               = [string]$dobj.Forest
    DnsRoot              = [string]$dobj.DNSRoot
    # compatibility / readability
    DomainController     = $dc
    DomainName           = $domain

  }
}
