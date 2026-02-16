function New-ADDiscoveryIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter()][string]$CustomerName,
        [Parameter(Mandatory)][string]$OutputPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Get-RelativePath([string]$FullName) {
        return $FullName.Substring($RunRoot.Length).TrimStart('\', '/')
    }

    function Get-RowCountFast([System.IO.FileInfo]$File) {
        if ($File.Extension -ne '.csv') { return $null }
        try {
            # Fast-ish row count without Import-Csv (header line excluded)
            $lines = 0
            $reader = [System.IO.File]::OpenText($File.FullName)
            try {
                while ($null -ne $reader.ReadLine()) { $lines++ }
            } finally {
                $reader.Dispose()
            }
            if ($lines -le 1) { return 0 }
            return ($lines - 1)
        } catch {
            return $null
        }
    }

    function Parse-DomainFqdnFromPath([string]$RelPath) {
        # Expected: 20_domains/Domain-contoso.com/...
        if ($RelPath -match '(^|/|\\)20_domains(/|\\)Domain-([^/\\]+)') {
            return $matches[3]
        }
        return $null
    }

    function Get-DatasetKind([string]$RelPath) {
        if ($RelPath -match '(^|/|\\)00_schemas(/|\\)') { return 'Schema' }
        if ($RelPath -match '(^|/|\\)10_forest(/|\\)') { return 'Forest' }
        if ($RelPath -match '(^|/|\\)20_domains(/|\\)') { return 'Domain' }
        if ($RelPath -match '(^|/|\\)90_logs(/|\\)') { return 'Log' }
        if ($RelPath -match '(^|/|\\)99_manifest(/|\\)') { return 'Manifest' }
        return 'Run'
    }

    function Get-CanonicalDatasetName([string]$RelPath) {
        # Map your known file naming into stable semantic names.
        # Keep this conservative; you can expand safely later.

        $p = $RelPath -replace '\\', '/'

        switch -Regex ($p) {
            '^10_forest/AD__Forest__Summary__Forest\.csv$' { 'Forest.Summary' ; break }
            '^10_forest/AD__Forest__Security__Trusts__Forest\.csv$' { 'Forest.Trusts' ; break }
            '^10_forest/AD__Forest__Network__Sites__Forest\.csv$' { 'Forest.Sites' ; break }
            '^10_forest/AD__Forest__Network__Subnets__Forest\.csv$' { 'Forest.Subnets' ; break }
            '^10_forest/AD__Forest__Network__SiteLinks__Forest\.csv$' { 'Forest.SiteLinks' ; break }
            '^10_forest/AD__Forest__Identity__UpnSuffixes__Forest\.csv$' { 'Forest.UpnSuffixes' ; break }

            '^20_domains/Domain-[^/]+/AD__Domain__Identity__Users__.+\.csv$' { 'Domain.Users' ; break }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__Groups__.+\.csv$' { 'Domain.Groups' ; break }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__ComputersAll__.+\.csv$' { 'Domain.Computers.All' ; break }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__ComputersServers__.+\.csv$' { 'Domain.Computers.Servers' ; break }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__ComputersWorkstations__.+\.csv$' { 'Domain.Computers.Workstations' ; break }

            '^20_domains/Domain-[^/]+/AD__Domain__Security__PasswordPolicyDefault__.+\.csv$' { 'Domain.PasswordPolicy.Default' ; break }
            '^20_domains/Domain-[^/]+/AD__Domain__Security__PasswordPolicyFgpp__.+\.csv$' { 'Domain.PasswordPolicy.FGPP' ; break }
            '^20_domains/Domain-[^/]+/AD__Domain__GPO__Inventory__.+\.csv$' { 'Domain.GPO.Inventory' ; break }
            '^20_domains/Domain-[^/]+/AD__Domain__GPO__Links__.+\.csv$' { 'Domain.GPO.Links' ; break }

            default {
                # Fall back to filename stem as “File.<stem>”
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($p)
                return "File.$stem"
            }
        }
    }

    function New-ADDiscoveryIndex {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][string]$Environment,
            [Parameter()][string]$CustomerName,
            [Parameter(Mandatory)][string]$OutputPath,

            # NEW (optional)
            [Parameter()][string[]]$Tags
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

        $index = [ordered]@{
            schemaVersion  = '1.0'
            tool           = 'Consulting.Toolkit.Discovery'
            toolVersion    = '0.1.0'
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            environment    = $Environment
            customerName   = $CustomerName
            runRoot        = $RunRoot
            tags           = @()
            datasets       = $datasets
        }

        if ($Tags) {
            $index.tags = @($Tags | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        }

        ($index | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    }


    $files = Get-ChildItem -LiteralPath $RunRoot -Recurse -File |
    Where-Object { $_.Extension -in '.csv', '.json' } |
    Where-Object {
        $_.FullName -notmatch '[\\/](30_analysis|40_assessment)[\\/]'
    }


    $datasets = foreach ($f in $files) {
        $rel = Get-RelativePath $f.FullName
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()

        $kind = Get-DatasetKind $rel
        $domainFqdn = if ($kind -eq 'Domain') { Parse-DomainFqdnFromPath $rel } else { $null }
        $name = Get-CanonicalDatasetName $rel
        $rows = Get-RowCountFast $f

        [pscustomobject]@{
            name             = $name
            kind             = $kind
            domainFqdn       = $domainFqdn
            contentType      = if ($f.Extension -eq '.csv') { 'text/csv' } else { 'application/json' }
            path             = $rel
            sha256           = $hash
            bytes            = $f.Length
            rows             = $rows
            lastWriteTimeUtc = $f.LastWriteTimeUtc.ToString('o')
            tags             = @()  # reserved for later
        }
    }

    $index = [pscustomobject]@{
        schemaVersion  = '1.0'
        contract       = 'Discovery.v1'
        tool           = 'Consulting.Toolkit.Discovery'
        toolVersion    = '0.1.0'
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        environment    = $Environment
        customerName   = $CustomerName
        runRoot        = $RunRoot
        datasets       = $datasets
    }

    $index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
