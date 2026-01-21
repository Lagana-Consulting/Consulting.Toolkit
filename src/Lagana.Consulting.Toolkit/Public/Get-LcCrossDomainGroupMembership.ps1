function Get-LcCrossDomainGroupMembership {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext
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
        $groups = @(Get-ADGroup -Filter * -Server $server -Properties Members -ErrorAction Stop)
    } catch {
        throw "Failed to enumerate groups for $domain via $server. $($_.Exception.Message)"
    }

    $results = @()
    foreach ($g in $groups) {
        if (-not $g.Members -or $g.Members.Count -eq 0) { continue }

        $crossDomainMembers = @()
        foreach ($memberDn in $g.Members) {
            # Extract domain from DN
            $dnParts = $memberDn -split ','
            $dcParts = $dnParts | Where-Object { $_ -like 'DC=*' }
            if ($dcParts) {
                $memberDomain = ($dcParts -replace 'DC=', '') -join '.'
                if ($memberDomain -and $memberDomain -ne $domain) {
                    $crossDomainMembers += "$memberDn|$memberDomain"
                }
            }
        }

        if ($crossDomainMembers.Count -gt 0) {
            $results += [pscustomobject]@{
                DomainFqdn             = $domain
                GroupName              = [string]$g.Name
                GroupDn                = [string]$g.DistinguishedName
                CrossDomainMemberCount = $crossDomainMembers.Count
                CrossDomainMembers     = ($crossDomainMembers -join ';')
            }
        }
    }

    return $results | Sort-Object -Property CrossDomainMemberCount -Descending
}
