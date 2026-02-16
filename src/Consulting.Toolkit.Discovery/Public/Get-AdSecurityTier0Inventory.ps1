function Get-AdSecurityTier0Inventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    # Returns a structured object with multiple datasets
    $members = @(Get-AdPrivilegedGroupMembers -DomainContext $DomainContext)
    $admin = @(Get-AdAdminCountObjects -DomainContext $DomainContext)
    $prot = @(Get-AdProtectedUsersMembers -DomainContext $DomainContext)

    [pscustomobject]@{
        PrivilegedGroupMembers = $members
        AdminCountObjects      = $admin
        ProtectedUsers         = $prot
    }
}
