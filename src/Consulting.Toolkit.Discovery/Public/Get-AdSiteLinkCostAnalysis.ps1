function Get-AdSiteLinkCostAnalysis {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Get-ADReplicationSiteLink -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADReplicationSiteLink missing)."
    }

    $siteLinks = Get-AdAdReplicationSiteLinks

    $results = @()
    foreach ($link in $siteLinks) {
        $assessment = if ($link.Cost -gt 1000) { 'Very High Cost' }
        elseif ($link.Cost -gt 500) { 'High Cost' }
        elseif ($link.Cost -gt 100) { 'Medium Cost' }
        else { 'Normal' }

        $results += [pscustomobject]@{
            Name                = [string]$link.Name
            Cost                = $link.Cost
            ReplicationInterval = $link.ReplicationFrequencyInMinutes
            SitesIncluded       = $link.SitesIncluded
            Assessment          = $assessment
            Recommendation      = if ($link.Cost -gt 500) { 'Review if cost is appropriate for bandwidth' } else { 'No action needed' }
        }
    }

    return $results | Sort-Object -Property Cost -Descending
}
