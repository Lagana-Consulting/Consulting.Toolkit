function Get-AdPrivilegedGroupMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    if (-not (Get-Command Get-ADGroup -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADGroup missing)."
    }

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn
    $privNames = @(Get-AdPrivilegedGroupNames)

    $rows = @()

    foreach ($gName in $privNames) {
        $g = $null
        try {
            $g = Get-ADGroup -Identity $gName -Server $server -ErrorAction Stop
        } catch {
            continue
        }

        $members = @(Get-AdGroupMembersRecursive -GroupDn $g.DistinguishedName -Server $server)

        foreach ($m in $members) {
            $rows += [pscustomobject]@{
                DomainFqdn           = $domain
                PrivilegedGroupName  = $gName
                MemberSamAccountName = $m.SamAccountName
                MemberDn             = $m.DistinguishedName
                MemberObjectClass    = $m.objectClass
            }
        }
    }

    return @($rows)
}
