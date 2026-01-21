function Get-LcAdComputers {
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

  $computers = @()
  try {
    $computers = @(Get-ADComputer -Filter * -Server $server -Properties $props -ErrorAction Stop |
      Sort-Object Name)
  } catch {
    throw "Failed to enumerate computers for $domain via $server. $($_.Exception.Message)"
  }

  foreach ($c in $computers) {
    $lltUtc = ConvertFrom-LcFileTime -FileTime $c.LastLogonTimestamp
    $lastLogonDays = Get-LcDaysSince -DateUtc $lltUtc -Now $nowUtc

    $spnCount = @($c.ServicePrincipalName).Count

    $encTypes = Convert-LcEncryptionTypes -EncryptionTypeValue $c.'msDS-SupportedEncryptionTypes'
    $encRisk = Get-LcEncryptionRisk    -EncryptionTypeValue $c.'msDS-SupportedEncryptionTypes'

    $os = [string]$c.OperatingSystem
    $isServer = Get-LcComputerIsServer -OperatingSystem $os

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

      MsDsSupportedEncryptionTypes = $c.'msDS-SupportedEncryptionTypes'
      EncryptionTypes              = ($encTypes -join ';')
      EncryptionRisk               = $encRisk

      Description                  = [string]$c.Description
    }
  }
}
