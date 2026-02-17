function Get-AdAdContacts {
    <#
  .SYNOPSIS
  Retrieves AD contact objects from a domain.

  .DESCRIPTION
  Queries Active Directory for contact objects (typically used for external email addresses
  and mail-enabled non-user entities). Returns properties useful for migration assessment
  and mail routing analysis.

  .PARAMETER DomainName
  Domain to query. If not specified, queries the current domain.

  .PARAMETER Server
  Domain controller or global catalog to query. Optional.

  .EXAMPLE
  Get-AdAdContacts

  Gets all AD contacts in the current domain.

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

    # Base properties that are always safe
    $baseProps = @(
        'displayName',
        'mail',
        'proxyAddresses'
    )
    # Only include Exchange-style attributes if they exist
    $schemaAttrs = Get-ADObject `
        -SearchBase (Get-ADRootDSE).schemaNamingContext `
        -LDAPFilter "(lDAPDisplayName=targetAddress)" `
        -ErrorAction SilentlyContinue

    if ($schemaAttrs) {
        $baseProps += 'targetAddress'
    }

    Get-ADObject -LDAPFilter "(objectClass=contact)" `
        -Properties $baseProps
}

