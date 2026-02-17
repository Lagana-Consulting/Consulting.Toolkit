function New-ADDiscoveryIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$Environment,
        [Parameter()][string]$CustomerName,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter()][string[]]$Tags
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Get-RelativePath([string]$FullName) {
        $FullName.Substring($RunRoot.Length).TrimStart('\', '/')
    }

    function Get-RowCountFast([System.IO.FileInfo]$File) {
        if ($File.Extension -ne '.csv') { return $null }
        try {
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
        if ($RelPath -match '(^|/|\\)20_domains(/|\\)Domain-([^/\\]+)') { return $matches[3] }
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
        $p = $RelPath -replace '\\', '/'

        switch -Regex ($p) {
            '^10_forest/AD__Forest__Summary__Forest\.csv$' { return 'Forest.Summary' }
            '^10_forest/AD__Forest__Security__Trusts__Forest\.csv$' { return 'Forest.Trusts' }
            '^10_forest/AD__Forest__Network__Sites__Forest\.csv$' { return 'Forest.Sites' }
            '^10_forest/AD__Forest__Network__Subnets__Forest\.csv$' { return 'Forest.Subnets' }
            '^10_forest/AD__Forest__Network__SiteLinks__Forest\.csv$' { return 'Forest.SiteLinks' }
            '^10_forest/AD__Forest__Identity__UpnSuffixes__Forest\.csv$' { return 'Forest.UpnSuffixes' }

            '^20_domains/Domain-[^/]+/AD__Domain__Identity__Users__.+\.csv$' { return 'Domain.Users' }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__Groups__.+\.csv$' { return 'Domain.Groups' }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__ComputersAll__.+\.csv$' { return 'Domain.Computers.All' }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__ComputersServers__.+\.csv$' { return 'Domain.Computers.Servers' }
            '^20_domains/Domain-[^/]+/AD__Domain__Identity__ComputersWorkstations__.+\.csv$' { return 'Domain.Computers.Workstations' }

            '^20_domains/Domain-[^/]+/AD__Domain__Security__PasswordPolicyDefault__.+\.csv$' { return 'Domain.PasswordPolicy.Default' }
            '^20_domains/Domain-[^/]+/AD__Domain__Security__PasswordPolicyFgpp__.+\.csv$' { return 'Domain.PasswordPolicy.FGPP' }
            '^20_domains/Domain-[^/]+/AD__Domain__GPO__Inventory__.+\.csv$' { return 'Domain.GPO.Inventory' }
            '^20_domains/Domain-[^/]+/AD__Domain__GPO__Links__.+\.csv$' { return 'Domain.GPO.Links' }
            '^20_domains/Domain-[^/]+/AD__Domain__GPO__Delegation__.+\.csv$' { return 'Domain.GPO.Delegation' }
            '^20_domains/Domain-[^/]+/AD__Domain__Security__RecentlyCreatedObjects__.+\.csv$' { return 'Domain.Security.RecentlyCreatedObjects' }
            '^20_domains/Domain-[^/]+/AD__Domain__Security__BuiltInAdministratorSignals__.+\.csv$' { return 'Domain.Security.BuiltInAdministratorSignals' }
            '^20_domains/Domain-[^/]+/AD__Domain__Security__AsrepRoastableUsers__.+\.csv$' { return 'Domain.Security.AsrepRoastableUsers' }
            '^20_domains/Domain-[^/]+/AD__Domain__Security__PrivilegedPasswordAge__.+\.csv$' { return 'Domain.Security.PrivilegedPasswordAge' }
            '^20_domains/Domain-[^/]+/AD__Domain__Security__AdminSdHolderImpact__.+\.csv$' { return 'Domain.Security.AdminSdHolderImpact' }

            default {
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($p)
                return "File.$stem"
            }
        }
    }

    $normalizedTags = @()
    if ($Tags) {
        $normalizedTags = @(
            $Tags |
            Where-Object { $_ } |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
        )
    }

    $files = Get-ChildItem -LiteralPath $RunRoot -Recurse -File |
    Where-Object { $_.Extension -in '.csv', '.json' } |
    Where-Object { $_.FullName -notmatch '[\\/](30_analysis|40_assessment)[\\/]' }

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
        }
    }

    $index = [ordered]@{
        schemaVersion  = '1.0'
        contract       = 'Discovery.v1'
        tool           = 'Consulting.Toolkit.Discovery'
        toolVersion    = '0.1.0'
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        environment    = $Environment
        customerName   = $CustomerName
        runRoot        = $RunRoot
        tags           = $normalizedTags
        datasets       = @($datasets)
    }

    $index | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
