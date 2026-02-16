#Requires -Version 7.2
Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-DotSource {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path
  )
  try {
    . $Path
  } catch {
    throw "Failed dot-sourcing '$Path' in module '$($MyInvocation.MyCommand.ModuleName)'. $($_.Exception.Message)"
  }
}

# Load Private first (helpers), then Public (exported functions)
$privateDir = Join-Path $script:ModuleRoot 'Private'
$publicDir = Join-Path $script:ModuleRoot 'Public'

if (Test-Path -LiteralPath $privateDir) {
  Get-ChildItem -LiteralPath $privateDir -Filter '*.ps1' -File -Recurse |
  Sort-Object FullName |
  ForEach-Object { Invoke-DotSource $_.FullName }
}

if (Test-Path -LiteralPath $publicDir) {
  Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -File -Recurse |
  Sort-Object FullName |
  ForEach-Object { Invoke-DotSource $_.FullName }
}

# Optional module init hook
$init = Join-Path $privateDir '_Init.ps1'
if (Test-Path -LiteralPath $init) { Invoke-DotSource $init }

# ---- Contract surface (what Discovery officially exports) ----
$exportRequested = @(
  'Invoke-AdDiscovery',        # legacy wrapper (kept for compatibility)
  'Invoke-AdDiscoveryExport',  # strict discovery export entrypoint

  # Core discovery primitives / building blocks
  'Get-AdAdForest',
  'Get-AdAdDomains',
  'Get-AdAdDomainContext',
  'New-AdRunLayout',

  # Export helpers
  'Export-AdCsvSafe',
  'Export-AdSchemas',

  # Logging
  'New-AdLog',
  'Write-AdLog'
)

# Export only functions that actually exist (avoids surprises if something is renamed)
$exportResolved = foreach ($name in $exportRequested) {
  if (Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue) { $name }
}

Export-ModuleMember -Function $exportResolved -Alias @()
