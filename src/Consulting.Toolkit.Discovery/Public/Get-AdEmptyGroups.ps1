function Get-AdEmptyGroups {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext
    )

    $details = Get-AdGroupMembershipDetails -DomainContext $DomainContext
    return @($details.EmptyGroups | Sort-Object -Property WhenCreated)
}
