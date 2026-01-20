Set-StrictMode -Version Latest

$PublicPath  = Join-Path $PSScriptRoot 'Public'
$PrivatePath = Join-Path $PSScriptRoot 'Private'

# Dot-source Private first
Get-ChildItem -Path $PrivatePath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
  . $_.FullName
}

# Dot-source Public
Get-ChildItem -Path $PublicPath -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
  . $_.FullName
}

# Export only public functions
Export-ModuleMember -Function @(
  'New-LcLog',
  'Write-LcLog',
  'Export-LcCsv',
  'Confirm-LcTenant',
  'Connect-LcGraph'
)
