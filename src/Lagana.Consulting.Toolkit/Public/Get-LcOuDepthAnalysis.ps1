function Get-LcOuDepthAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        [int]$WarningDepth = 5
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    $domain = [string]$DomainContext.DomainFqdn

    # Get all OUs
    $ous = Get-LcAdOrganizationalUnits -DomainContext $DomainContext

    $results = @()
    foreach ($ou in $ous) {
        $depth = $ou.Level

        $results += [pscustomobject]@{
            DomainFqdn        = $domain
            Name              = [string]$ou.Name
            DistinguishedName = [string]$ou.DistinguishedName
            Depth             = $depth
            DepthWarning      = if ($depth -ge $WarningDepth) { 'High' } else { 'Normal' }
            IsTopLevel        = $ou.IsTopLevel
        }
    }

    return $results | Sort-Object -Property Depth -Descending
}
