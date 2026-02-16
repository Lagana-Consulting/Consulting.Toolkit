function Get-AdProtectedUsersMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    $server = $DomainContext.Server
    $domain = $DomainContext.DomainFqdn

    $g = $null
    try {
        $g = Get-ADGroup -Identity 'Protected Users' -Server $server -ErrorAction Stop
    } catch {
        return @()
    }

    $members = @(Get-AdGroupMembersRecursive -GroupDn $g.DistinguishedName -Server $server)

    foreach ($m in $members) {
        [pscustomobject]@{
            DomainFqdn           = $domain
            GroupName            = 'Protected Users'
            MemberSamAccountName = $m.SamAccountName
            MemberDn             = $m.DistinguishedName
            MemberObjectClass    = $m.objectClass
        }
    }
}
