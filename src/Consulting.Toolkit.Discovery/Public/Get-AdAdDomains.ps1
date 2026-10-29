function Get-AdAdDomains {
  <#
  .SYNOPSIS
  Retrieves list of domain names from an AD forest.

  .DESCRIPTION
  Returns a normalized array of domain FQDNs from the specified forest.
  Domains are returned in lowercase, trimmed, and deduplicated. Can accept
  a forest object to avoid redundant queries.

  .PARAMETER Forest
  Forest object from Get-AdAdForest. If provided, ForestName parameter is ignored.
  Use this when you already have a forest object to avoid redundant queries.

  .PARAMETER ForestName
  Name of the forest to query. Ignored if Forest parameter is provided.

  .PARAMETER Server
  Domain controller or global catalog to query. Used only if Forest parameter
  is not provided.

  .EXAMPLE
  $domains = Get-AdAdDomains

  Gets all domains in the current forest.

  .EXAMPLE
  Get-AdAdDomains -ForestName "contoso.com"

  Gets all domains in the contoso.com forest.

  .EXAMPLE
  $forest = Get-AdAdForest -ForestName "fabrikam.com"
  $domains = Get-AdAdDomains -Forest $forest

  Reuses forest object to avoid redundant query.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  System.String[]. Array of domain FQDNs (lowercase, sorted, unique).

  .NOTES
  Normalizes domain names to lowercase for consistency.
  Requires Active Directory PowerShell module.

  .LINK
  Get-AdAdForest
  #>
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
    throw
  }

  # Normalize to lower-case and distinct
  $domains = $domains | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique
  return $domains
}
