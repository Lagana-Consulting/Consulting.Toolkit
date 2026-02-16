function Invoke-SATWebScan {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$Urls,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$OutputRoot,

        [switch]$IUnderstandThisIsIntrusive
    )

    Set-StrictMode -Version Latest

    $profileData = Read-AssessmentProfile -Profile $Profile
    if ($profileData.Web.RequiresConsent -and -not $IUnderstandThisIsIntrusive) {
        throw 'This profile may be intrusive. Re-run with -IUnderstandThisIsIntrusive to continue.'
    }

    $assessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    $logPath = Join-Path $assessmentPath 'assessment.log'
    $toolVersionsPath = Join-Path $assessmentPath 'tool_versions.txt'

    Write-SATLog -Message "Invoke-SATWebScan started. Profile=$Profile" -LogPath $logPath

    $zapReport = Join-Path $assessmentPath 'zap_report.html'
    $tlsReport = Join-Path $assessmentPath 'tls_report.txt'
    $headersCsv = Join-Path $assessmentPath 'http_headers.csv'

    $headersData = @()
    foreach ($url in $Urls) {
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction Stop
            foreach ($headerName in $response.Headers.Keys) {
                $headersData += [pscustomobject]@{
                    Url        = $url
                    Header     = $headerName
                    Value      = $response.Headers[$headerName]
                    Timestamp  = (Get-Date -Format 's')
                    SourceTool = 'Invoke-WebRequest'
                }
            }
        } catch {
            Write-SATLog -Message "HTTP header collection failed for $url" -LogPath $logPath
        }
    }

    if ($headersData.Count -gt 0) {
        $headersData | Export-Csv -Path $headersCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-SATCsv -Path $headersCsv -Headers @('Url', 'Header', 'Value', 'Timestamp', 'SourceTool')
    }

    $testssl = Get-Command -Name 'testssl' -ErrorAction SilentlyContinue
    $sslscan = Get-Command -Name 'sslscan' -ErrorAction SilentlyContinue

    if ($testssl) {
        Add-Content -Path $toolVersionsPath -Value "testssl: $((Get-SATToolVersion -Command 'testssl' -VersionArgs @('--version')))"
        foreach ($url in $Urls) {
            Write-SATLog -Message "Command: testssl $url" -LogPath $logPath
            & $testssl.Source @($url) | Add-Content -Path $tlsReport
        }
    } elseif ($sslscan) {
        Add-Content -Path $toolVersionsPath -Value "sslscan: $((Get-SATToolVersion -Command 'sslscan' -VersionArgs @('--version')))"
        foreach ($url in $Urls) {
            Write-SATLog -Message "Command: sslscan $url" -LogPath $logPath
            & $sslscan.Source @($url) | Add-Content -Path $tlsReport
        }
    } else {
        Set-Content -Path $tlsReport -Value 'TLS tooling not found. Skipped.'
        Write-SATLog -Message 'testssl/sslscan not found. Skipped TLS scan.' -LogPath $logPath
    }

    $zap = Get-Command -Name 'zap' -ErrorAction SilentlyContinue
    if ($zap -and $profileData.Web.ZapMode -eq 'Active') {
        Write-SATLog -Message 'ZAP detected but not automatically invoked in this scaffold.' -LogPath $logPath
        Set-Content -Path $zapReport -Value '<html><body><h1>ZAP execution not configured in this scaffold.</h1></body></html>'
    } else {
        Set-Content -Path $zapReport -Value '<html><body><h1>ZAP not executed.</h1></body></html>'
    }

    Write-SATLog -Message "Invoke-SATWebScan completed. OutputPath=$assessmentPath" -LogPath $logPath
    return [pscustomobject]@{
        AssessmentPath = $assessmentPath
        Scope          = 'Web'
        EvidenceFiles  = @($zapReport, $tlsReport, $headersCsv)
        FindingIds     = @()
    }
}
