function Get-AdUnconstrainedDelegation {
    <#
  .SYNOPSIS
  Identifies accounts with unconstrained delegation enabled.

  .DESCRIPTION
  Returns user and computer accounts where the TRUSTED_FOR_DELEGATION flag is set
  (unconstrained delegation). Results are read-only and intended for security review.

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext. Required.

  .EXAMPLE
  $ctx = Get-AdAdDomainContext -DomainFqdn "contoso.com"
  Get-AdUnconstrainedDelegation -DomainContext $ctx

  .OUTPUTS
  PSCustomObject[] with properties:
  - DomainFqdn, ObjectClass, SamAccountName, Name, DistinguishedName, Enabled, SPNCount

  .NOTES
  Requires Active Directory PowerShell module.
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    if (-not (Get-Command Get-ADComputer -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADComputer missing)."
    }

    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADUser missing)."
    }

    $domain = [string]$DomainContext.DomainFqdn
    $server = [string]$DomainContext.Server

    $results = @()

    $ldapFilter = '(userAccountControl:1.2.840.113556.1.4.803:=524288)'
    $props = @('TrustedForDelegation', 'ServicePrincipalName', 'Enabled')

    $computers = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADComputer' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
        param($queryServer)
        Get-ADComputer -LDAPFilter $ldapFilter -SearchBase $DomainContext.DomainDn -SearchScope Subtree -Server $queryServer -Properties $props -ErrorAction Stop
    })

    foreach ($c in $computers) {
        $results += [pscustomobject]@{
            DomainFqdn        = $domain
            ObjectClass       = 'computer'
            SamAccountName    = [string]$c.SamAccountName
            Name              = [string]$c.Name
            DistinguishedName = [string]$c.DistinguishedName
            Enabled           = [bool]$c.Enabled
            SPNCount          = @($c.ServicePrincipalName).Count
        }
    }

    $users = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADUser' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
        param($queryServer)
        Get-ADUser -LDAPFilter $ldapFilter -SearchBase $DomainContext.DomainDn -SearchScope Subtree -Server $queryServer -Properties $props -ErrorAction Stop
    })

    foreach ($u in $users) {
        $results += [pscustomobject]@{
            DomainFqdn        = $domain
            ObjectClass       = 'user'
            SamAccountName    = [string]$u.SamAccountName
            Name              = [string]$u.Name
            DistinguishedName = [string]$u.DistinguishedName
            Enabled           = [bool]$u.Enabled
            SPNCount          = @($u.ServicePrincipalName).Count
        }
    }

    return $results
}
