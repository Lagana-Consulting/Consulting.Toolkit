function Get-AdAdPublishedPrinters {
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
        'name', 'displayName', 'serverName', 'uNCName', 'location', 'description',
        'printShareName', 'driverName', 'distinguishedName', 'whenCreated', 'whenChanged'
    )

    $propsFallback = @(
        'name', 'displayName', 'distinguishedName', 'whenCreated', 'whenChanged'
    )

    $printers = @()
    try {
        $printers = @(Get-ADObject -LDAPFilter '(objectClass=printQueue)' -SearchBase $domainDn -Server $server -Properties $propsPreferred -ErrorAction Stop |
            Sort-Object Name)
    } catch {
        if ($_.Exception.Message -match 'properties are invalid') {
            try {
                $printers = @(Get-ADObject -LDAPFilter '(objectClass=printQueue)' -SearchBase $domainDn -Server $server -Properties $propsFallback -ErrorAction Stop |
                    Sort-Object Name)
            } catch {
                # Retry against the requested domain as final fallback
                try {
                    $printers = @(Get-ADObject -LDAPFilter '(objectClass=printQueue)' -SearchBase $domainDn -Server $DomainContext.DomainFqdn -Properties $propsFallback -ErrorAction Stop |
                        Sort-Object Name)
                } catch {
                    throw
                }
            }
        } else {
            # Retry against the requested domain as fallback
            try {
                $printers = @(Get-ADObject -LDAPFilter '(objectClass=printQueue)' -SearchBase $domainDn -Server $DomainContext.DomainFqdn -Properties $propsPreferred -ErrorAction Stop |
                    Sort-Object Name)
            } catch {
                throw
            }
        }
    }

    Assert-AdDiscoveryDomainRows -Rows $printers -ExpectedDomainDn $domainDn

    foreach ($p in $printers) {
        [pscustomobject]@{
            DomainFqdn        = [string]$DomainContext.DomainFqdn
            Name              = [string]$p.Name
            DisplayName       = $(if ($p.PSObject.Properties['DisplayName']) { [string]$p.DisplayName } else { '' })
            ServerName        = $(if ($p.PSObject.Properties['ServerName']) { [string]$p.ServerName } else { '' })
            UNCName           = $(if ($p.PSObject.Properties['uNCName']) { [string]$p.uNCName } else { '' })
            PrintShareName    = $(if ($p.PSObject.Properties['printShareName']) { [string]$p.printShareName } else { '' })
            DriverName        = $(if ($p.PSObject.Properties['DriverName']) { [string]$p.DriverName } else { '' })
            Location          = $(if ($p.PSObject.Properties['Location']) { [string]$p.Location } else { '' })
            Description       = $(if ($p.PSObject.Properties['Description']) { [string]$p.Description } else { '' })
            DistinguishedName = [string]$p.DistinguishedName
            WhenCreated       = $p.whenCreated
            WhenChanged       = $p.whenChanged
        }
    }
}
