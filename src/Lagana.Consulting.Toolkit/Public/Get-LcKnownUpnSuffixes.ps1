function Get-LcKnownUpnSuffixes {
  [CmdletBinding()]
  param(
    [object]$Forest,

    [string[]]$Domains,

    [string]$ForestName,

    [string]$Server,

    # If set, returns a hashtable for fast lookups: $set.ContainsKey("contoso.com")
    [switch]$AsHashSet
  )

  if (-not $Forest) {
    $Forest = Get-LcAdForest -ForestName $ForestName -Server $Server
  }

  if (-not $Domains) {
    $Domains = Get-LcAdDomains -Forest $Forest
  }

  $suffixes = New-Object System.Collections.Generic.List[string]

  # Forest UPN suffixes
  try {
    if ($Forest.UPNSuffixes) {
      foreach ($s in $Forest.UPNSuffixes) {
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $suffixes.Add($s.Trim().ToLowerInvariant())
      }
    }
  } catch {
    # If this fails, keep going; it's not always populated.
  }

  # Root domain is always a "known suffix" candidate
  try {
    if ($Forest.RootDomain) {
      $suffixes.Add(([string]$Forest.RootDomain).Trim().ToLowerInvariant())
    }
  } catch {
    # ignore
  }

  # Domains are also common UPN suffix candidates
  foreach ($d in @($Domains)) {
    if ([string]::IsNullOrWhiteSpace($d)) { continue }
    $suffixes.Add($d.Trim().ToLowerInvariant())
  }

  # Distinct
  $distinct = $suffixes.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

  if ($AsHashSet) {
    # Use hashtable as a simple, fast lookup set
    $set = @{}
    foreach ($s in $distinct) { $set[$s] = $true }
    return $set
  }

  return $distinct
}
