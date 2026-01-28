function Get-AdAdPublishedSharedFolders {
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

    $server = [string]$DomainContext.Server
    $domainDn = [string]$DomainContext.DomainDn

    $props = @(
        'name', 'uNCName', 'description', 'volumePath',
        'distinguishedName', 'whenCreated', 'whenChanged'
    )

    $shares = @()
    try {
        $shares = @(Get-ADObject -LDAPFilter '(objectClass=volume)' -SearchBase $domainDn -Server $server -Properties $props -ErrorAction Stop |
            Sort-Object Name)
    } catch {
        throw "Failed to enumerate published shared folders for $($DomainContext.DomainFqdn) via $server. $($_.Exception.Message)"
    }

    foreach ($s in $shares) {
        [pscustomobject]@{
            DomainFqdn        = [string]$DomainContext.DomainFqdn
            Name              = [string]$s.Name
            UNCName           = [string]$s.uNCName
            VolumePath        = [string]$s.volumePath
            Description       = [string]$s.Description
            DistinguishedName = [string]$s.DistinguishedName
            WhenCreated       = $s.whenCreated
            WhenChanged       = $s.whenChanged
        }
    }
}
