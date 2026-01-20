function Get-LcGpoLinks {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object]$DomainContext,

    [ValidateSet('OneLevel','Subtree')]
    [string]$Scope = 'OneLevel'
  )

  if (-not (Get-Command Get-ADOrganizationalUnit -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADOrganizationalUnit missing)."
  }

  $domain = [string]$DomainContext.DomainFqdn
  $server = [string]$DomainContext.Server
  $baseDn = [string]$DomainContext.DomainDn

  # gPLink contains bracketed links: [LDAP://cn={GUID},cn=policies,cn=system,DC=...;0][...;2]
  $ous = @(Get-ADOrganizationalUnit -Filter * -SearchBase $baseDn -SearchScope $Scope -Server $server -Properties gPLink,gPOptions -ErrorAction Stop)

  foreach ($ou in $ous) {
    $gpLink = [string]$ou.gPLink
    if ([string]::IsNullOrWhiteSpace($gpLink)) { continue }

    $matches = [regex]::Matches($gpLink, '\[LDAP://(?<dn>[^;]+);(?<opt>\d+)\]')
    foreach ($m in $matches) {
      $policyDn = $m.Groups['dn'].Value
      $opt = [int]$m.Groups['opt'].Value

      # Extract GUID if present in CN={GUID}
      $guid = $null
      $gm = [regex]::Match($policyDn, 'CN=\{(?<g>[0-9A-Fa-f-]+)\}')
      if ($gm.Success) { $guid = $gm.Groups['g'].Value }

      [pscustomobject]@{
        DomainFqdn        = $domain
        OuName            = [string]$ou.Name
        OuDistinguishedName = [string]$ou.DistinguishedName
        GpoPolicyDn       = $policyDn
        GpoGuid           = $guid
        LinkOption        = $opt
        LinkEnabled       = ($opt -band 1) -eq 0    # 1 means disabled
        Enforced          = ($opt -band 2) -ne 0    # 2 means enforced
        GpOptions         = [int]($ou.gPOptions -as [int])
      }
    }
  }
}
