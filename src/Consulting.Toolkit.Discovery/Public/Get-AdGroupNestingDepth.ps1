function Get-AdGroupNestingDepth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        [int]$WarningDepth = 5
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    if (-not (Get-Command Get-ADGroup -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADGroup missing)."
    }

    $domain = [string]$DomainContext.DomainFqdn
    $server = [string]$DomainContext.Server

    $groups = @()
    try {
        $groups = @(Get-ADGroup -Filter * -Server $server -Properties MemberOf, objectSid -ErrorAction Stop)
    } catch {
        throw "Failed to enumerate groups for $domain via $server. $($_.Exception.Message)"
    }

    $results = @()
    foreach ($g in @($groups | Where-Object { -not (Test-AdBuiltInGroup -Group $_) })) {
        $depth = 0
        $currentGroup = $g
        $visited = @{}

        # Traverse up the group hierarchy
        while ($currentGroup.MemberOf -and $currentGroup.MemberOf.Count -gt 0) {
            $depth++

            # Get the first parent group (simplification - groups can have multiple parents)
            $parentDn = $currentGroup.MemberOf | Select-Object -First 1

            if ($visited.ContainsKey($parentDn)) {
                # Circular reference detected
                $depth = -1
                break
            }

            $visited[$parentDn] = $true

            try {
                $currentGroup = Get-ADGroup -Identity $parentDn -Server $server -Properties MemberOf -ErrorAction Stop
            } catch {
                Write-AdDiscoveryCollectionIssue -Message "Could not read parent group '$parentDn'; nesting depth is incomplete." -ErrorRecord $_
                # Parent not found, stop traversal
                break
            }

            # Safety limit
            if ($depth -gt 50) {
                $depth = -1
                break
            }
        }

        $results += [pscustomobject]@{
            DomainFqdn        = $domain
            Name              = [string]$g.Name
            SamAccountName    = [string]$g.SamAccountName
            DistinguishedName = [string]$g.DistinguishedName
            NestingDepth      = $depth
            DepthWarning      = if ($depth -ge $WarningDepth) { 'High' } elseif ($depth -eq -1) { 'Circular' } else { 'Normal' }
        }
    }

    return $results | Sort-Object -Property NestingDepth -Descending
}
