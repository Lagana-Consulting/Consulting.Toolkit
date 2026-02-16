function New-ADDiscoveryIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter()][string]$CustomerName,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $files = Get-ChildItem -LiteralPath $RunRoot -Recurse -File |
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
        schemaVersion  = '1.0'
        tool           = 'Consulting.Toolkit.Discovery'
        toolVersion    = '0.1.0'
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        environment    = $Environment
        customerName   = $CustomerName
        runRoot        = $RunRoot
        datasets       = $datasets
    }

    $index | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
