function Get-AdPrivilegedPasswordAge {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext
  )

  if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADUser missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = if ($DomainContext.Server) { [string]$DomainContext.Server } else { [string]$DomainContext.DomainController }

  $priv = @(Get-AdPrivilegedAccounts -DomainContext $DomainContext)
  if (-not $priv -or $priv.Count -eq 0) { return @() }

  $now = Get-Date

  foreach ($p in $priv) {
    try {
      $u = Get-ADUser -Identity $p.DistinguishedName -Server $server -Properties Enabled,PasswordLastSet,pwdLastSet,objectGuid -ErrorAction Stop
      $pls = $u.PasswordLastSet
      $ageDays = if ($pls) { [int]([math]::Floor(($now - $pls).TotalDays)) } else { $null }

      [pscustomobject]@{
        DomainFqdn         = $domain
        SamAccountName     = [string]$u.SamAccountName
        DistinguishedName  = [string]$u.DistinguishedName
        ObjectGuid         = [string]$u.ObjectGuid
        Enabled            = [bool]$u.Enabled
        InPrivGroups       = [bool]$p.InPrivGroups
        PrivGroups         = [string]$p.PrivGroups
        AdminCount         = [bool]$p.AdminCount
        PasswordLastSet    = $pls
        PasswordAgeDays    = $ageDays
      }
    } catch {
      Write-AdDiscoveryCollectionIssue -Message "Could not read privileged account password age: $($p.DistinguishedName)" -ErrorRecord $_
    }
  }
}
