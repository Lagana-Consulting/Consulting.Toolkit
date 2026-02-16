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

# Export ONLY functions that exist in Public\
$publicFunctions = @()
if (Test-Path -LiteralPath $publicDir) {
  $publicFunctions =
  Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -File |
  ForEach-Object { $_.BaseName } |
  Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } |
  Sort-Object -Unique
}

Export-ModuleMember -Function $publicFunctions
