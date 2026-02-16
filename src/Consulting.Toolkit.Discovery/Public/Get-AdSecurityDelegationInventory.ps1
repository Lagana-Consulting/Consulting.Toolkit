function Get-AdSecurityDelegationInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $DomainContext)

    [pscustomobject]@{
        Unconstrained      = @(Get-AdDelegationUnconstrained -DomainContext $DomainContext)
        Constrained        = @(Get-AdDelegationConstrained -DomainContext $DomainContext)
        ProtocolTransition = @(Get-AdDelegationProtocolTransition -DomainContext $DomainContext)
        RBCD               = @(Get-AdDelegationRBCD -DomainContext $DomainContext)
    }
}
