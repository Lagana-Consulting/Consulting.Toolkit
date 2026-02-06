function Get-AdAdForestSummary {
  [CmdletBinding()]
  param(
    [object]$Forest,
    [string]$ForestName,
    [string]$Server
  )

  if (-not $Forest) {
    $Forest = Get-AdAdForest -ForestName $ForestName -Server $Server
  }

  $domains = Get-AdAdDomains -Forest $Forest
  $suffixes = @()
  try { $suffixes = @($Forest.UPNSuffixes) } catch { $suffixes = @() }

  [pscustomobject]@{
    ForestName        = [string]$Forest.Name
    RootDomain        = [string]$Forest.RootDomain
    ForestMode        = [string]$Forest.ForestMode
    Domains           = ($domains -join ';')
    DomainCount       = ($domains | Measure-Object).Count
    UPNSuffixes       = ((@($suffixes) | Where-Object { $_ }) -join ';')
    UPNSuffixCount    = ((@($suffixes) | Where-Object { $_ }) | Measure-Object).Count
    SchemaMaster      = [string]$Forest.SchemaMaster
    DomainNamingMaster= [string]$Forest.DomainNamingMaster
  }
}
