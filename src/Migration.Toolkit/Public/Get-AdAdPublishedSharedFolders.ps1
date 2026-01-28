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

    $propsPreferred = @(
        'name', 'uNCName', 'volumePath', 'description',
        'distinguishedName', 'whenCreated', 'whenChanged'
    )

    $propsFallback = @(
        'name', 'uNCName', 'description',
        'distinguishedName', 'whenCreated', 'whenChanged'
    )

    $shares = @()
    try {
        $shares = @(Get-ADObject -LDAPFilter '(objectClass=volume)' -SearchBase $domainDn -Server $server -Properties $propsPreferred -ErrorAction Stop |
            Sort-Object Name)
    } catch {
        if ($_.Exception.Message -match 'properties are invalid|invalid property|volumePath') {
            try {
                $shares = @(Get-ADObject -LDAPFilter '(objectClass=volume)' -SearchBase $domainDn -Server $server -Properties $propsFallback -ErrorAction Stop |
                    Sort-Object Name)
            } catch {
                throw "Failed to enumerate published shared folders for $($DomainContext.DomainFqdn) via $server. $($_.Exception.Message)"
            }
        } else {
            throw "Failed to enumerate published shared folders for $($DomainContext.DomainFqdn) via $server. $($_.Exception.Message)"
        }
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
