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
        [string]$DomainName,
        [string]$Server
    )

    if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available. Install RSAT AD tools / Import-Module ActiveDirectory."
    }

    $params = @{
        Filter     = 'ObjectClass -eq "contact"'
        Properties = @(
            'SamAccountName',
            'mail',
            'targetAddress',
            'proxyAddresses',
            'Created',
            'Modified',
            'DistinguishedName',
            'ObjectGUID',
            'msExchMailboxGuid'
        )
    }

    if ($DomainName) {
        $params['SearchBase'] = "DC=$($DomainName.Replace('.', ',DC='))"
    }
    if ($Server) {
        $params['Server'] = $Server
    }

    try {
        $contacts = Get-ADObject @params -ErrorAction Stop

        return $contacts | ForEach-Object {
            [pscustomobject]@{
                Name              = $_.Name
                SamAccountName    = $_.SamAccountName
                Mail              = $_.mail
                TargetAddress     = $_.targetAddress
                ProxyAddresses    = ($_.proxyAddresses -join '; ')
                Created           = $_.Created
                Modified          = $_.Modified
                DistinguishedName = $_.DistinguishedName
                ObjectGUID        = $_.ObjectGUID
                MailEnabled       = (-not [string]::IsNullOrWhiteSpace($_.mail))
                HasMailboxGuid    = ($null -ne $_.msExchMailboxGuid)
                ObjectClass       = $_.ObjectClass
            }
        }
    }
    catch {
        $target = if ($DomainName) { $DomainName } else { 'current domain' }
        throw "Failed to query AD contacts from $target. $($_.Exception.Message)"
    }
}
