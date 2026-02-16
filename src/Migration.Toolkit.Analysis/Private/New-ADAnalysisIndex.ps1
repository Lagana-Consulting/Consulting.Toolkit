function New-ADAnalysisIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$AnalysisDir,
        [Parameter(Mandatory)][string]$DiscoveryIndexPath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $files = Get-ChildItem -LiteralPath $AnalysisDir -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.csv', '.json' }

    $datasets = foreach ($f in $files) {
        $rel = $f.FullName.Substring($RunRoot.Length).TrimStart('\', '/')
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
        [pscustomobject]@{
            path             = $rel
            sha256           = $hash
            bytes            = $f.Length
            lastWriteTimeUtc = $f.LastWriteTimeUtc.ToString('o')
        }
    }

    $index = [pscustomobject]@{
        schemaVersion      = '1.0'
        contract           = 'Analysis.v1'
        tool               = 'Migration.Toolkit.Analysis'
        toolVersion        = '0.1.0'
        generatedAtUtc     = (Get-Date).ToUniversalTime().ToString('o')
        discoveryIndexPath = $DiscoveryIndexPath
        datasets           = $datasets
    }

    $index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
