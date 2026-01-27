function Get-AdAdDomains {
  [CmdletBinding()]
  param(
    # Pass a forest object if you already have it (saves repeat calls)
    [object]$Forest,

    # Or query a specific forest by name
    [string]$ForestName,

    # Optional DC/GC to query against
    [string]$Server
  )

  if (-not $Forest) {
    $Forest = Get-AdAdForest -ForestName $ForestName -Server $Server
  }

  $domains = @()

  try {
    # Get-ADForest.Domains is typically a string collection
    $domains = @($Forest.Domains | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  } catch {
    throw "Could not read domains from forest object. $($_.Exception.Message)"
  }

  # Normalize to lower-case and distinct
  $domains = $domains | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique
  return $domains
}
