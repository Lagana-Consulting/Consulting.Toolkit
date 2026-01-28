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
                throw "Failed to enumerate published printers for $($DomainContext.DomainFqdn) via $server. $($_.Exception.Message)"
            }
        } else {
            throw "Failed to enumerate published printers for $($DomainContext.DomainFqdn) via $server. $($_.Exception.Message)"
        }
    }

    foreach ($p in $printers) {
        [pscustomobject]@{
            DomainFqdn        = [string]$DomainContext.DomainFqdn
            Name              = [string]$p.Name
            DisplayName       = [string]$p.DisplayName
            ServerName        = [string]$p.ServerName
            UNCName           = [string]$p.uNCName
            PrintShareName    = [string]$p.printShareName
            DriverName        = [string]$p.DriverName
            Location          = [string]$p.Location
            Description       = [string]$p.Description
            DistinguishedName = [string]$p.DistinguishedName
            WhenCreated       = $p.whenCreated
            WhenChanged       = $p.whenChanged
        }
    }
}
