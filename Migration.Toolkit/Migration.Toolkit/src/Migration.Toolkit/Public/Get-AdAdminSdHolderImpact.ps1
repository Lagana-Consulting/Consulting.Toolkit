function Get-AdAdminSdHolderImpact {
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

    $domain = [string]$DomainContext.DomainFqdn
    $server = [string]$DomainContext.Server

    # Query objects with adminCount=1
    $filter = 'adminCount -eq 1'
    $props = @('objectClass', 'whenCreated', 'whenChanged', 'adminCount')

    $objects = @()
    try {
        $objects = @(Get-ADObject -Filter $filter -Server $server -Properties $props -ErrorAction Stop)
    } catch {
        throw "Failed to query adminCount objects for $domain via $server. $($_.Exception.Message)"
    }

    $results = @()
    foreach ($obj in $objects) {
        $results += [pscustomobject]@{
            DomainFqdn        = $domain
            ObjectClass       = [string]$obj.objectClass
            Name              = [string]$obj.Name
            DistinguishedName = [string]$obj.DistinguishedName
            WhenCreated       = $obj.whenCreated
            WhenChanged       = $obj.whenChanged
            AdminCount        = [int]$obj.adminCount
            Impact            = 'ACL inheritance disabled'
        }
    }

    return $results | Sort-Object -Property ObjectClass, Name
}
