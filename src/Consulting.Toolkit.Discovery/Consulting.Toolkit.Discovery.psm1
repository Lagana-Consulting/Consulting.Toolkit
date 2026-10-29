# Consulting.Toolkit.Discovery.psm1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$publicDir = Join-Path $moduleRoot 'Public'
$privateDir = Join-Path $moduleRoot 'Private'

# Dot-source all Private functions first (helpers)
if (Test-Path -LiteralPath $privateDir) {
  Get-ChildItem -LiteralPath $privateDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
  Sort-Object Name |
  ForEach-Object {
    . $_.FullName
  }
}

# Dot-source all Public functions
if (Test-Path -LiteralPath $publicDir) {
  Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
  Sort-Object Name |
  ForEach-Object {
    . $_.FullName
  }
}

# The manifest is the single source of truth for the supported public API.
# Some supported helpers live in Private for historical source-path compatibility.
$manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'Consulting.Toolkit.Discovery.psd1')
$publicFunctions = @($manifest.FunctionsToExport)
foreach ($name in $publicFunctions) {
  $command = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
  if (-not $command -or $command.ModuleName -ne $ExecutionContext.SessionState.Module.Name) {
    throw "Declared discovery export '$name' is missing from this module. Check the module package."
  }
}
Export-ModuleMember -Function $publicFunctions
