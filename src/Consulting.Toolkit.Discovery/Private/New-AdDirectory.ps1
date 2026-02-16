function New-AdDirectory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Path
  )

  $fullPath = Resolve-AdPath -Path $Path

  if (-not (Test-Path -LiteralPath $fullPath)) {
    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
  }

  return $fullPath
}
