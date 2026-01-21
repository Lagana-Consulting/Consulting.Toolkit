function Get-LcTopSpnsByType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        [int]$Top = 10
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    $domain = [string]$DomainContext.DomainFqdn

    # Get all SPNs
    $allSpns = Get-LcAdSpns -DomainContext $DomainContext

    # Extract service type (first part before /)
    $spnTypes = $allSpns | ForEach-Object {
        $spnValue = $_.ServicePrincipalName
        $serviceType = if ($spnValue -match '^([^/]+)/') { $Matches[1] } else { 'Unknown' }

        [pscustomobject]@{
            ServiceType = $serviceType
            SPN         = $spnValue
        }
    }

    # Group by service type and count
    $results = $spnTypes |
    Group-Object -Property ServiceType |
    ForEach-Object {
        [pscustomobject]@{
            DomainFqdn  = $domain
            ServiceType = $_.Name
            Count       = $_.Count
            ExampleSPN  = ($_.Group | Select-Object -First 1).SPN
        }
    } |
    Sort-Object -Property Count -Descending |
    Select-Object -First $Top

    return $results
}
