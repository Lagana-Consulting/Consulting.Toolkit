function Get-LcTombstoneLifetime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADObject missing)."
    }

    $domain = [string]$DomainContext.DomainFqdn
    $server = [string]$DomainContext.Server

    # Get configuration naming context
    $rootDSE = Get-ADRootDSE -Server $server
    $configNC = $rootDSE.configurationNamingContext

    # Query tombstoneLifetime from CN=Directory Service,CN=Windows NT,CN=Services
    $dsPath = "CN=Directory Service,CN=Windows NT,CN=Services,$configNC"

    try {
        $ds = Get-ADObject -Identity $dsPath -Server $server -Properties tombstoneLifetime -ErrorAction Stop
        $tombstoneValue = $ds.tombstoneLifetime

        # Default is 180 days if not set
        if (-not $tombstoneValue) { $tombstoneValue = 180 }

        $status = if ($tombstoneValue -lt 180) { 'Low (Risk)' } elseif ($tombstoneValue -ge 180) { 'Acceptable' } else { 'Unknown' }

        [pscustomobject]@{
            DomainFqdn        = $domain
            TombstoneLifetime = [int]$tombstoneValue
            Status            = $status
            Recommendation    = if ($tombstoneValue -lt 180) { 'Increase to at least 180 days' } else { 'No action needed' }
        }
    } catch {
        throw "Failed to query tombstoneLifetime for $domain via $server. $($_.Exception.Message)"
    }
}
