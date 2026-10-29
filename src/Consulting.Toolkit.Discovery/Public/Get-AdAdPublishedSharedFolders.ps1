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
                # Retry against the requested domain as final fallback
                try {
                    $shares = @(Get-ADObject -LDAPFilter '(objectClass=volume)' -SearchBase $domainDn -Server $DomainContext.DomainFqdn -Properties $propsFallback -ErrorAction Stop |
                        Sort-Object Name)
                } catch {
                    throw
                }
            }
        } else {
            # Retry against the requested domain as fallback
            try {
                $shares = @(Get-ADObject -LDAPFilter '(objectClass=volume)' -SearchBase $domainDn -Server $DomainContext.DomainFqdn -Properties $propsPreferred -ErrorAction Stop |
                    Sort-Object Name)
            } catch {
                throw
            }
        }
    }

    Assert-AdDiscoveryDomainRows -Rows $shares -ExpectedDomainDn $domainDn

    foreach ($s in $shares) {
        [pscustomobject]@{
            DomainFqdn        = [string]$DomainContext.DomainFqdn
            Name              = [string]$s.Name
            UNCName           = [string]$s.uNCName
            VolumePath        = $(if ($s.PSObject.Properties['volumePath']) { [string]$s.volumePath } else { '' })
            Description       = [string]$s.Description
            DistinguishedName = [string]$s.DistinguishedName
            WhenCreated       = $s.whenCreated
            WhenChanged       = $s.whenChanged
        }
    }
}
