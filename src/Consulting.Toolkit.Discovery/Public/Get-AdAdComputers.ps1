function Get-AdAdComputers {
  <#
  .SYNOPSIS
  Retrieves all computer accounts from a domain with migration-relevant properties.

  .DESCRIPTION
  Enumerates all computer accounts with comprehensive properties for migration:
  - Account status (enabled, last logon)
  - Operating system and server detection
  - SPN count and encryption types
  - Risk assessment (weak encryption, stale accounts)

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext. Required.

  .PARAMETER Now
  Reference timestamp for age calculations. Defaults to current date/time.
  Used for calculating LastLogonDays.

  .EXAMPLE
  $ctx = Get-AdAdDomainContext -DomainFqdn "contoso.com"
  $computers = Get-AdAdComputers -DomainContext $ctx

  Gets all computer accounts in contoso.com.

  .EXAMPLE
  $computers | Where-Object IsServer | Select-Object Name, OperatingSystem, LastLogonDays

  Shows all server accounts with last logon age.

  .EXAMPLE
  $computers | Where-Object { $_.LastLogonDays -gt 90 -and $_.Enabled }

  Finds enabled computers that haven't logged on in 90+ days (stale accounts).

  .EXAMPLE
  $computers | Where-Object { $_.EncryptionRisk -eq 'High' }

  Identifies computers with weak encryption types.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  PSCustomObject[]. Computer objects with properties:
  - Account: Name, SamAccountName, DNSHostName, Enabled
  - OS: OperatingSystem, OperatingSystemVersion, IsServer
  - Activity: WhenCreated, LastLogonDays
  - Risk: SpnCount, EncryptionTypes, EncryptionRisk

  .NOTES
  Requires Active Directory PowerShell module.
  LastLogonTimestamp is replicated (not real-time, ~14 day replication delay).
  IsServer detection based on OS name pattern matching.

  .LINK
  Get-AdAdDomainContext
  Get-ADComputer
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    $Now = (Get-Date)
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADComputer -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADComputer missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server
  $nowUtc = $Now.ToUniversalTime()

  $props = @(
    'Enabled', 'DNSHostName', 'OperatingSystem', 'OperatingSystemVersion',
    'whenCreated', 'whenChanged', 'LastLogonTimestamp',
    'ServicePrincipalName', 'msDS-SupportedEncryptionTypes', 'Description'
  )

  $computers = @(Invoke-AdDiscoveryQuery -Operation 'Get-ADComputer' -Server $server -DomainFqdn $domain -ExpectedDomainDn $DomainContext.DomainDn -RetryInDomain -Query {
    param($queryServer)
    $queryParams = @{ Filter = '*'; SearchBase = $DomainContext.DomainDn; SearchScope = 'Subtree'; ErrorAction = 'Stop' }
    $queryParams.Properties = $props
    if ($queryServer) { $queryParams.Server = $queryServer }
    Get-ADComputer @queryParams | Sort-Object Name
  })

  foreach ($c in $computers) {
    $lltUtc = ConvertFrom-AdFileTime -FileTime $c.LastLogonTimestamp
    $lastLogonDays = Get-AdDaysSince -DateUtc $lltUtc -Now $nowUtc

    $spnCount = @($c.ServicePrincipalName).Count

    # Handle msDS-SupportedEncryptionTypes safely (may not exist in older domains or on all objects)
    $encTypesValue = if ($c.PSObject.Properties['msDS-SupportedEncryptionTypes']) { $c.'msDS-SupportedEncryptionTypes' } else { $null }
    $encTypes = Convert-AdEncryptionTypes -EncryptionTypeValue $encTypesValue
    $encRisk = Get-AdEncryptionRisk    -EncryptionTypeValue $encTypesValue

    $os = [string]$c.OperatingSystem
    $isServer = Get-AdComputerIsServer -OperatingSystem $os

    [pscustomobject]@{
      DomainFqdn                   = $domain
      Name                         = [string]$c.Name
      SamAccountName               = [string]$c.SamAccountName
      DistinguishedName            = [string]$c.DistinguishedName
      Enabled                      = [bool]$c.Enabled
      DnsHostName                  = [string]$c.DNSHostName

      OperatingSystem              = $os
      OperatingSystemVersion       = [string]$c.OperatingSystemVersion
      IsServer                     = [bool]$isServer

      WhenCreated                  = $c.whenCreated
      WhenChanged                  = $c.whenChanged

      LastLogonTimestampUtc        = $lltUtc
      LastLogonDays                = $lastLogonDays

      SPNCount                     = [int]$spnCount

      MsDsSupportedEncryptionTypes = $encTypesValue
      EncryptionTypes              = ($encTypes -join ';')
      EncryptionRisk               = $encRisk

      Description                  = [string]$c.Description
    }
  }
}
