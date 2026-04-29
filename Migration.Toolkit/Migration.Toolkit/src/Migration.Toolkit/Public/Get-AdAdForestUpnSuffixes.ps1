function Get-AdAdForestUpnSuffixes {
  [CmdletBinding()]
  param(
    [object]$Forest,
    [string[]]$Domains,
    [string]$ForestName,
    [string]$Server
  )

  if (-not $Forest) {
    $Forest = Get-AdAdForest -ForestName $ForestName -Server $Server
  }
  if (-not $Domains) {
    $Domains = Get-AdAdDomains -Forest $Forest
  }

  $knownSet = Get-AdKnownUpnSuffixes -Forest $Forest -Domains $Domains -AsHashSet

  $suffixes = @()
  try { $suffixes = @($Forest.UPNSuffixes) } catch { $suffixes = @() }

  foreach ($s in ($suffixes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)) {
    [pscustomobject]@{
      Suffix          = $s
      IsKnownSuffix   = [bool]$knownSet.ContainsKey($s)
      IsNonRoutable   = [bool](Test-AdNonRoutableSuffix -Suffix $s)
    }
  }
}
