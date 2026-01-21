function Get-LcServiceAccountCandidates {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    $Now = (Get-Date)
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

  $props = @('Enabled', 'UserPrincipalName', 'ServicePrincipalName', 'PasswordLastSet', 'PasswordNeverExpires', 'LastLogonTimestamp', 'whenCreated', 'description')

  $users = @(Get-ADUser -Filter * -Server $server -Properties $props -ErrorAction Stop)

  foreach ($u in $users) {
    $spnCount = @($u.ServicePrincipalName).Count
    $pwdNever = [bool]($u.PasswordNeverExpires -as [bool])

    $lltUtc = ConvertFrom-LcFileTime -FileTime $u.LastLogonTimestamp
    $lastLogonDays = Get-LcDaysSince -DateUtc $lltUtc -Now $nowUtc

    $pwdUtc = if ($u.PasswordLastSet) { ([datetime]$u.PasswordLastSet).ToUniversalTime() } else { $null }
    $passwordAgeDays = Get-LcDaysSince -DateUtc $pwdUtc -Now $nowUtc

    # Heuristics
    $name = [string]$u.SamAccountName
    $looksLikeSvc = $name -match '^(svc|sql|app|sa|service)[-_]'

    $candidate = ($spnCount -gt 0) -or $pwdNever -or $looksLikeSvc
    if (-not $candidate) { continue }

    [pscustomobject]@{
      DomainFqdn           = $domain
      SamAccountName       = $name
      Enabled              = [bool]$u.Enabled
      UserPrincipalName    = [string]$u.UserPrincipalName
      WhenCreated          = $u.whenCreated
      SPNCount             = [int]$spnCount
      PasswordNeverExpires = $pwdNever
      LastLogonDays        = $lastLogonDays
      PasswordAgeDays      = $passwordAgeDays
      HeuristicFlags       = (@(
          if ($spnCount -gt 0) { 'HasSPN' }
          if ($pwdNever) { 'PwdNeverExpires' }
          if ($looksLikeSvc) { 'NamePattern' }
        ) | Where-Object { $_ }) -join ';'
      Description          = [string]$u.description
    }
  }
}
