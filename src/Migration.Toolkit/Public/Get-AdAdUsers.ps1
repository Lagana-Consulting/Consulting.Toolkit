function Get-AdAdUsers {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    $Now = (Get-Date),

    # For routability flags – pass the set from Get-AdKnownUpnSuffixes -AsHashSet
    [hashtable]$KnownUpnSuffixSet
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADUser missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server
  $nowUtc = $Now.ToUniversalTime()

  $props = @(
    'Enabled', 'UserPrincipalName', 'Mail', 'whenCreated', 'whenChanged',
    'LastLogonTimestamp', 'PasswordLastSet', 'adminCount', 'SIDHistory',
    'ServicePrincipalName', 'msDS-SupportedEncryptionTypes', 'Description'
  )

  $users = @()
  try {
    $users = @(Get-ADUser -Filter * -Server $server -Properties $props -ErrorAction Stop |
      Sort-Object SamAccountName)
  } catch {
    throw "Failed to enumerate users for $domain via $server. $($_.Exception.Message)"
  }

  foreach ($u in $users) {
    $upnSuffix = Get-AdUpnSuffix -UserPrincipalName $u.UserPrincipalName
    $isNonRoutable = if ($upnSuffix) { Test-AdNonRoutableSuffix -Suffix $upnSuffix } else { $true }

    $isKnownSuffix = $null
    if ($KnownUpnSuffixSet -and $upnSuffix) {
      $isKnownSuffix = [bool]$KnownUpnSuffixSet.ContainsKey($upnSuffix)
    }

    $lltUtc = ConvertFrom-AdFileTime -FileTime $u.LastLogonTimestamp
    $lastLogonDays = Get-AdDaysSince -DateUtc $lltUtc -Now $nowUtc

    $pwdUtc = if ($u.PasswordLastSet) { ([datetime]$u.PasswordLastSet).ToUniversalTime() } else { $null }
    $passwordAgeDays = Get-AdDaysSince -DateUtc $pwdUtc -Now $nowUtc

    $sidHistoryCount = @($u.SIDHistory).Count
    $spnCount = @($u.ServicePrincipalName).Count

    $encTypes = Convert-AdEncryptionTypes -EncryptionTypeValue $u.'msDS-SupportedEncryptionTypes'
    $encRisk = Get-AdEncryptionRisk    -EncryptionTypeValue $u.'msDS-SupportedEncryptionTypes'

    [pscustomobject]@{
      DomainFqdn                   = $domain
      SamAccountName               = [string]$u.SamAccountName
      Name                         = [string]$u.Name
      DistinguishedName            = [string]$u.DistinguishedName
      Enabled                      = [bool]$u.Enabled
      UserPrincipalName            = [string]$u.UserPrincipalName
      Mail                         = [string]$u.Mail
      UPNSuffix                    = $upnSuffix
      IsKnownUpnSuffix             = $isKnownSuffix
      IsNonRoutableUpnSuffix       = [bool]$isNonRoutable
      WhenCreated                  = $u.whenCreated
      WhenChanged                  = $u.whenChanged

      LastLogonTimestampUtc        = $lltUtc
      LastLogonDays                = $lastLogonDays

      PasswordLastSetUtc           = $pwdUtc
      PasswordAgeDays              = $passwordAgeDays

      AdminCount                   = [int]($u.adminCount -as [int])
      SidHistoryCount              = [int]$sidHistoryCount
      SPNCount                     = [int]$spnCount

      MsDsSupportedEncryptionTypes = $u.'msDS-SupportedEncryptionTypes'
      EncryptionTypes              = ($encTypes -join ';')
      EncryptionRisk               = $encRisk

      Description                  = [string]$u.Description
    }
  }
}
