function Test-LcNonRoutableSuffix {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [string]$Suffix
  )

  if ([string]::IsNullOrWhiteSpace($Suffix)) { return $true }

  $s = $Suffix.Trim().ToLowerInvariant()

  # Common internal / non-routable patterns
  if ($s -match '\.local$') { return $true }
  if ($s -match '\.internal$') { return $true }
  if ($s -match '\.lan$') { return $true }
  if ($s -match '\.corp$') { return $true }
  if ($s -match '\.home$') { return $true }
  if ($s -match '\.intra$') { return $true }

  return $false
}
