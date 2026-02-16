function Invoke-AdDiscoveryExport {
    [CmdletBinding()]
    param(
        [Parameter()][string]$Environment = "Source",
        [Parameter()][string]$OutputRoot = "c:\scripts\Reports",
        [Parameter()][string]$Prefix = "",
        [Parameter()][string]$CustomerName = "",
        [Parameter()][string]$Server,
        [Parameter()][int]$StaleUserThresholdDays = 180,
        [Parameter()][int]$StaleComputerThresholdDays = 90
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # --- existing: forest discovery + layout creation (reuse your helpers)
    $now = Get-Date
    $envTag = $Environment.ToLower().Replace(' ', '_')

    $forestParams = @{}
    if ($Server) { $forestParams.Server = $Server }
    $forest = Get-AdAdForest @forestParams
    $domains = @(Get-AdAdDomains -Forest $forest)
    $suffixSet = Get-AdKnownUpnSuffixes -Forest $forest -Domains $domains -AsHashSet

    $rootDomainTag = if ([string]::IsNullOrWhiteSpace($forest.RootDomain)) { 'unknowndomain' } else { $forest.RootDomain.ToLower().Replace(' ', '_') }
    $basePrefix = if ($Prefix) { $Prefix } else { "AD_{0}" -f $rootDomainTag }
    $envPrefix = if ($envTag -eq "source") { $basePrefix } else { "${basePrefix}__${envTag}" }

    $layout = New-AdRunLayout -OutputRoot $OutputRoot -Prefix $envPrefix -CreateLog

    # --- ensure folders (keep your structure)
    $schemasDir = Join-Path $layout.RunRoot '00_schemas'
    $forestDir = Join-Path $layout.RunRoot '10_forest'
    $domainsRoot = Join-Path $layout.RunRoot '20_domains'
    $manifestDir = Join-Path $layout.RunRoot '99_manifest'
    $logsDir = Join-Path $layout.RunRoot '90_logs'
    foreach ($p in @($schemasDir, $forestDir, $domainsRoot, $manifestDir, $logsDir)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }

    # --- export schemas (still allowed in discovery)
    Export-AdSchemas -SchemasDir $schemasDir | Out-Null

    # --- EXPORTS ONLY (no derived analysis datasets here)
    (Get-AdAdForestSummary -Forest $forest) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Summary__Forest.csv') -Force -AllowEmpty

    (Get-AdAdForestTrusts -LogPath $layout.LogPath) |
    Export-AdCsvSafe -Path (Join-Path $forestDir 'AD__Forest__Security__Trusts__Forest.csv') -Force -AllowEmpty

    foreach ($d in $domains) {
        $ctxParams = @{ DomainFqdn = $d; LogPath = $layout.LogPath }
        if ($Server) { $ctxParams.Server = $Server }
        $ctx = Get-AdAdDomainContext @ctxParams
        $scopeTag = "Domain-$($ctx.DomainFqdn)"
        $domainDir = Join-Path $domainsRoot $scopeTag
        New-Item -ItemType Directory -Force -Path $domainDir | Out-Null

        # inventory exports
        (Get-AdAdDomainSummary -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Summary__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdAdDomainControllers -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Infrastructure__DomainControllers__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        $users = @(Get-AdAdUsers -DomainContext $ctx -Now $now -KnownUpnSuffixSet $suffixSet)
        $groups = @(Get-AdAdGroups -DomainContext $ctx)
        $comps = @(Get-AdAdComputers -DomainContext $ctx -Now $now)

        $users  | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Users__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
        $groups | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Groups__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
        $comps  | Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__ComputersAll__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        # security inventories (still “raw”)
        (Get-AdUsersSidHistory -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Security__UsersSidHistory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdAdSpns -DomainContext $ctx) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__Identity__Spns__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdGpoInventory -DomainContext $ctx -LogPath $layout.LogPath) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Inventory__{0}.csv" -f $scopeTag)) -Force -AllowEmpty

        (Get-AdGpoLinks -DomainContext $ctx -Scope OneLevel) |
        Export-AdCsvSafe -Path (Join-Path $domainDir ("AD__Domain__GPO__Links__{0}.csv" -f $scopeTag)) -Force -AllowEmpty
    }

    # --- strict discovery index (contract)
    $indexPath = Join-Path $manifestDir 'Discovery__Index__Run.json'
    New-ADDiscoveryIndex -RunRoot $layout.RunRoot -Environment $Environment -CustomerName $CustomerName -OutputPath $indexPath

    return [pscustomobject]@{
        RunRoot       = $layout.RunRoot
        LogPath       = $layout.LogPath
        Environment   = $Environment
        ForestName    = $forest.Name
        DomainCount   = $domains.Count
        IndexPath     = $indexPath
        ExecutionTime = $now
    }
}
