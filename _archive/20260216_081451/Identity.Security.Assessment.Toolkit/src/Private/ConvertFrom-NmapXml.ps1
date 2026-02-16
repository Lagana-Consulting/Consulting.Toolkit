function ConvertFrom-NmapXml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Timestamp = (Get-Date -Format 's')
    )

    if (-not (Test-Path $Path)) {
        return [pscustomobject]@{
            Hosts    = @()
            Ports    = @()
            Services = @()
        }
    }

    $xml = [xml](Get-Content -Path $Path -Raw)
    $hosts = @()
    $ports = @()
    $services = @()

    foreach ($host in $xml.nmaprun.host) {
        if ($host.status.state -ne 'up') { continue }

        $ip = ($host.address | Where-Object { $_.addrtype -eq 'ipv4' } | Select-Object -First 1).addr
        $hostname = ($host.hostnames.hostname | Select-Object -First 1).name
        $osGuess = ($host.os.osmatch | Select-Object -First 1).name

        $hosts += [pscustomobject]@{
            Target     = $hostname
            IP         = $ip
            Hostname   = $hostname
            OSGuess    = $osGuess
            FirstSeen  = $Timestamp
            LastSeen   = $Timestamp
            SourceTool = 'nmap'
        }

        foreach ($port in $host.ports.port) {
            $serviceName = $port.service.name
            $version = $port.service.version
            $ports += [pscustomobject]@{
                IP          = $ip
                Port        = $port.portid
                Proto       = $port.protocol
                State       = $port.state.state
                Service     = $serviceName
                Version     = $version
                ScanProfile = 'nmap'
                Timestamp   = $Timestamp
            }
            $services += [pscustomobject]@{
                IP        = $ip
                Port      = $port.portid
                Proto     = $port.protocol
                Service   = $serviceName
                Version   = $version
                Timestamp = $Timestamp
            }
        }
    }

    return [pscustomobject]@{
        Hosts    = $hosts
        Ports    = $ports
        Services = $services
    }
}
