function Invoke-SATDiscovery {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$Targets,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$OutputRoot,

        [string]$MaxRate,

        [string]$ScanDelay,

        [string[]]$Exclude,

        [switch]$IUnderstandThisIsIntrusive
    )

    Set-StrictMode -Version Latest

    $profileData = Read-AssessmentProfile -Profile $Profile
    if ($profileData.Nmap.RequiresConsent -and -not $IUnderstandThisIsIntrusive) {
        throw 'This profile may be intrusive. Re-run with -IUnderstandThisIsIntrusive to continue.'
    }

    $assessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    $logPath = Join-Path $assessmentPath 'assessment.log'
    $toolVersionsPath = Join-Path $assessmentPath 'tool_versions.txt'

    Write-SATLog -Message "Invoke-SATDiscovery started. Profile=$Profile" -LogPath $logPath

    $nmapVersion = Get-SATToolVersion -Command 'nmap' -VersionArgs @('--version')
    if ($nmapVersion) {
        Add-Content -Path $toolVersionsPath -Value "nmap: $nmapVersion"
    }

    $hostsCsv = Join-Path $assessmentPath 'hosts.csv'
    $portsCsv = Join-Path $assessmentPath 'ports.csv'
    $servicesJson = Join-Path $assessmentPath 'services.json'
    $dnsCsv = Join-Path $assessmentPath 'dns.csv'
    $nmapXml = Join-Path $assessmentPath 'nmap.xml'

    $hostsHeaders = @('Target', 'IP', 'Hostname', 'OSGuess', 'FirstSeen', 'LastSeen', 'SourceTool')
    $portsHeaders = @('IP', 'Port', 'Proto', 'State', 'Service', 'Version', 'ScanProfile', 'Timestamp')
    $dnsHeaders = @('Target', 'Query', 'RecordType', 'RecordData', 'Timestamp', 'SourceTool')

    $nmap = Get-Command -Name 'nmap' -ErrorAction SilentlyContinue
    if (-not $nmap) {
        Write-Warning 'nmap not found. Creating empty artifacts.'
        Write-SATLog -Message 'nmap not found. Skipped scan.' -LogPath $logPath
        New-SATCsv -Path $hostsCsv -Headers $hostsHeaders
        New-SATCsv -Path $portsCsv -Headers $portsHeaders
        Set-Content -Path $servicesJson -Value '[]'
    } else {
        $args = @()
        if ($profileData.Nmap.Arguments) {
            $args += ($profileData.Nmap.Arguments -split '\s+')
        }
        if ($MaxRate) {
            $args += @('--max-rate', $MaxRate)
        }
        if ($ScanDelay) {
            $args += @('--scan-delay', $ScanDelay)
        }
        if ($Exclude) {
            $args += @('--exclude', ($Exclude -join ','))
        }
        $args += @('-oX', $nmapXml)
        $args += $Targets

        Write-SATLog -Message ("Command: nmap {0}" -f ($args -join ' ')) -LogPath $logPath
        & $nmap.Source @args | Out-Null

        $timestamp = Get-Date -Format 's'
        $parsed = ConvertFrom-NmapXml -Path $nmapXml -Timestamp $timestamp

        if ($parsed.Hosts.Count -gt 0) {
            $parsed.Hosts | Export-Csv -Path $hostsCsv -NoTypeInformation -Encoding UTF8
        } else {
            New-SATCsv -Path $hostsCsv -Headers $hostsHeaders
        }

        if ($parsed.Ports.Count -gt 0) {
            $parsed.Ports | Export-Csv -Path $portsCsv -NoTypeInformation -Encoding UTF8
        } else {
            New-SATCsv -Path $portsCsv -Headers $portsHeaders
        }

        $parsed.Services | ConvertTo-Json -Depth 4 | Set-Content -Path $servicesJson
    }

    $dnsRecords = @()
    foreach ($target in $Targets) {
        try {
            $records = Resolve-DnsName -Name $target -ErrorAction Stop
            foreach ($record in $records) {
                $recordData = $null
                if ($record.IPAddress) {
                    $recordData = $record.IPAddress
                } elseif ($record.NameHost) {
                    $recordData = $record.NameHost
                } else {
                    $recordData = $record.StringRepresentation
                }
                $dnsRecords += [pscustomobject]@{
                    Target     = $target
                    Query      = $record.Name
                    RecordType = $record.Type
                    RecordData = $recordData
                    Timestamp  = (Get-Date -Format 's')
                    SourceTool = 'Resolve-DnsName'
                }
            }
        } catch {
            Write-SATLog -Message "DNS resolution failed for $target" -LogPath $logPath
        }
    }

    if ($dnsRecords.Count -gt 0) {
        $dnsRecords | Export-Csv -Path $dnsCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-SATCsv -Path $dnsCsv -Headers $dnsHeaders
    }

    Write-SATLog -Message "Invoke-SATDiscovery completed. OutputPath=$assessmentPath" -LogPath $logPath
    return [pscustomobject]@{
        AssessmentPath = $assessmentPath
        Scope          = 'Discovery'
        EvidenceFiles  = @($hostsCsv, $portsCsv, $servicesJson, $dnsCsv, $nmapXml)
        FindingIds     = @()
    }
}
