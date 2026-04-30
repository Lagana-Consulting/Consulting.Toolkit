function Get-AdDuplicateSpns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    $domain = [string]$DomainContext.DomainFqdn

    # Get all SPNs
    $allSpns = Get-AdAdSpns -DomainContext $DomainContext

    # Group by SPN value
    $duplicates = $allSpns |
    Group-Object -Property ServicePrincipalName |
    Where-Object { $_.Count -gt 1 }

    $results = @()
    foreach ($dup in $duplicates) {
        $spn = $dup.Name
        $objects = $dup.Group

        $results += [pscustomobject]@{
            DomainFqdn           = $domain
            ServicePrincipalName = $spn
            ConflictCount        = $dup.Count
            ConflictingObjects   = (($objects | ForEach-Object { $_.SamAccountName }) -join ';')
            ConflictingDNs       = (($objects | ForEach-Object { $_.DistinguishedName }) -join ';')
            RiskLevel            = 'High'
        }
    }

    return $results | Sort-Object -Property ConflictCount -Descending
}
