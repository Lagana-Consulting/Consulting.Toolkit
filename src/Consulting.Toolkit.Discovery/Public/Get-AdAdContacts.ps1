function Get-AdAdContacts {
    <#
  .SYNOPSIS
  Retrieves AD contact objects from a domain.

  .DESCRIPTION
  Queries Active Directory for contact objects (typically used for external email addresses
  and mail-enabled non-user entities). Returns properties useful for migration assessment
  and mail routing analysis.

  .PARAMETER DomainName
  Domain to query. Required.

  .PARAMETER Server
  Domain controller to query. Required; domain-scoped failover is supported.

  .EXAMPLE
  Get-AdAdContacts -DomainName "corp.contoso.com" -Server "dc01.corp.contoso.com"

  Queries contacts from specific domain using specific DC.

  .OUTPUTS
  PSCustomObject with contact properties:
  - Name, SamAccountName, DistinguishedName
  - Mail, TargetAddress, ProxyAddresses
  - Created, Modified
  - ObjectGUID, ObjectClass

  .NOTES
  Requires Active Directory PowerShell module (RSAT).
  Useful for identifying external email addresses and mail-enabled contacts.

  .LINK
  Get-ADObject
  Get-AdAdUsers
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DomainName,
        [Parameter(Mandatory)][string]$Server
    )

    Set-StrictMode -Version Latest

    $ctx = Get-AdAdDomainContext -DomainFqdn $DomainName -Server $Server
    $root = Get-ADRootDSE -Server $ctx.Server -ErrorAction Stop
    $baseProps = @('displayName', 'mail', 'proxyAddresses')
    # Absence of an optional schema attribute is a valid result. A failed schema
    # read must propagate rather than silently changing the requested properties.
    $schemaAttrs = @(Get-ADObject -SearchBase $root.schemaNamingContext -Server $ctx.Server `
        -LDAPFilter '(lDAPDisplayName=targetAddress)' -ErrorAction Stop)
    if ($schemaAttrs.Count -gt 0) { $baseProps += 'targetAddress' }

    Invoke-AdDiscoveryQuery -Operation 'Contacts' -Server $ctx.Server -DomainFqdn $ctx.DomainFqdn `
        -ExpectedDomainDn $ctx.DomainDn -RetryInDomain -Query {
        param($queryServer)
        Get-ADObject -LDAPFilter '(objectClass=contact)' -SearchBase $ctx.DomainDn -SearchScope Subtree `
            -Server $queryServer -Properties $baseProps -ErrorAction Stop
    }
}
