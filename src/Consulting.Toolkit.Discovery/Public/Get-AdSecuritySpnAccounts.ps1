function Get-AdSecuritySpnAccounts {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    return @(Get-AdSpnAccounts -DomainContext $DomainContext)
}
