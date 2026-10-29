function Get-AdDuplicateSpns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        [AllowEmptyCollection()][object[]]$Spns
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    $domain = [string]$DomainContext.DomainFqdn

    # Get all SPNs
    $allSpns = if ($PSBoundParameters.ContainsKey('Spns')) { @($Spns) } else { @(Get-AdAdSpns -DomainContext $DomainContext) }
    $normalized = foreach ($row in $allSpns) {
        [pscustomobject]@{
            ServicePrincipalName = Resolve-AdSpnValue -Row $row
            SamAccountName = [string]$row.SamAccountName
            DistinguishedName = [string]$row.DistinguishedName
        }
    }

    # Group by SPN value
    $duplicates = $normalized |
    Group-Object -Property ServicePrincipalName |
    Where-Object { $_.Count -gt 1 }

    $results = @()
    foreach ($dup in $duplicates) {
        $spn = $dup.Name
        # Duplicate rows for one owner do not represent conflicting registrations.
        $objects = @($dup.Group | Sort-Object -Property DistinguishedName -Unique)
        if ($objects.Count -lt 2) { continue }

        $results += [pscustomobject]@{
            DomainFqdn           = $domain
            ServicePrincipalName = $spn
            ConflictCount        = $objects.Count
            ConflictingObjects   = (($objects | ForEach-Object { $_.SamAccountName }) -join ';')
            ConflictingDNs       = (($objects | ForEach-Object { $_.DistinguishedName }) -join ';')
            RiskLevel            = 'High'
        }
    }

    return $results | Sort-Object -Property ConflictCount -Descending
}
