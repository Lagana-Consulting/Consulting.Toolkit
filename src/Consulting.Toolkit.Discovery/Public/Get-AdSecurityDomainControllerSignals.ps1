function Get-AdSecurityDomainControllerSignals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $DomainContext
    )

    if (-not (Get-Command Get-ADDomainController -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADDomainController missing)."
    }

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn

    $dcs = @()
    try {
        $dcs = @(Get-ADDomainController -Filter * -Server $server -ErrorAction Stop)
    } catch {
        # fallback: try without -Server
        $dcs = @(Get-ADDomainController -Filter * -ErrorAction Stop)
    }

    foreach ($dc in $dcs) {
        $dcName = if ($dc.HostName) { [string]$dc.HostName } else { [string]$dc.Name }
        foreach ($signal in @(
            @{ N = 'IsGlobalCatalog'; V = [string][bool]$dc.IsGlobalCatalog; E = 'Get-ADDomainController' }
            @{ N = 'IsReadOnly';      V = [string][bool]$dc.IsReadOnly;      E = 'Get-ADDomainController' }
            @{ N = 'OperatingSystem'; V = [string]$dc.OperatingSystem;       E = 'Get-ADDomainController' }
            @{ N = 'OSVersion';       V = [string]$dc.OperatingSystemVersion;E = 'Get-ADDomainController' }
            @{ N = 'Site';            V = [string]$dc.Site;                  E = 'Get-ADDomainController' }
            @{ N = 'IPv4Address';     V = [string]$dc.IPv4Address;           E = 'Get-ADDomainController' }
        )) {
            [pscustomobject]@{
                DomainFqdn       = $domain
                DomainController = $dcName
                Signal           = $signal.N
                Value            = $signal.V
                Evidence         = $signal.E
            }
        }
    }
}
