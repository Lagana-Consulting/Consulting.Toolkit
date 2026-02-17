function Get-AdGpoLinks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $DomainContext,

    [ValidateSet('OneLevel','Subtree')]
    [string]$Scope = 'Subtree',

    [string]$LogPath
  )

  if (-not $DomainContext) {
    throw "DomainContext cannot be null."
  }

  if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADObject missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server
  $baseDn = [string]$DomainContext.DomainDn

  # gPLink can exist on domainDNS and organizationalUnit objects.
  # (Site links live in Configuration NC and are out-of-scope for this domain collector.)
  $targets = @()
  try {
    $targets = @(
      Get-ADObject -LDAPFilter '(&(|(objectClass=domainDNS)(objectClass=organizationalUnit))(gPLink=*))' `
        -SearchBase $baseDn -SearchScope $Scope -Server $server `
        -Properties gPLink,gPOptions,distinguishedName,name,objectClass -ErrorAction Stop
    )
  } catch {
    if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Failed to enumerate GPO links in {0}. {1}" -f $domain, $_.Exception.Message) }
    throw
  }

  foreach ($target in $targets) {
    $gpLink = [string]$target.gPLink
    if ([string]::IsNullOrWhiteSpace($gpLink)) { continue }

    $matches = [regex]::Matches(
      $gpLink,
      '\[LDAP://(?<dn>[^;]+);(?<opt>\d+)\]',
      [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    foreach ($m in $matches) {
      $policyDn = $m.Groups['dn'].Value
      $opt = [int]$m.Groups['opt'].Value

      # Extract GUID if present in CN={GUID}
      $guid = $null
      $gm = [regex]::Match($policyDn, 'CN=\{(?<g>[0-9A-Fa-f-]+)\}')
      if ($gm.Success) { $guid = $gm.Groups['g'].Value }

      $targetType = if (@($target.objectClass) -contains 'domainDNS') { 'Domain' } else { 'OU' }

      [pscustomobject]@{
        DomainFqdn            = $domain
        OuName                = [string]$target.Name
        OuDistinguishedName   = [string]$target.DistinguishedName
        LinkTargetType        = $targetType
        LinkTargetName        = [string]$target.Name
        LinkTargetDistinguishedName = [string]$target.DistinguishedName
        GpoPolicyDn           = $policyDn
        GpoGuid               = $guid
        LinkOption            = $opt
        LinkEnabled           = ($opt -band 1) -eq 0    # 1 means disabled
        Enforced              = ($opt -band 2) -ne 0    # 2 means enforced
        GpOptions             = [int]($target.gPOptions -as [int])
      }
    }
  }
}
