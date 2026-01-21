function Get-LcEmptyGroups {
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
        $groups = @(Get-ADGroup -Filter * -Server $server -Properties Members, WhenCreated, WhenChanged, Description -ErrorAction Stop)
    } catch {
        throw "Failed to enumerate groups for $domain via $server. $($_.Exception.Message)"
    }

    $results = @()
    foreach ($g in $groups) {
        if (-not $g.Members -or $g.Members.Count -eq 0) {
            $results += [pscustomobject]@{
                DomainFqdn        = $domain
                Name              = [string]$g.Name
                SamAccountName    = [string]$g.SamAccountName
                DistinguishedName = [string]$g.DistinguishedName
                GroupCategory     = [string]$g.GroupCategory
                GroupScope        = [string]$g.GroupScope
                WhenCreated       = $g.WhenCreated
                WhenChanged       = $g.WhenChanged
                Description       = [string]$g.Description
            }
        }
    }

    return $results | Sort-Object -Property WhenCreated
}
