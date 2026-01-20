function Export-LcCsv {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [object[]]$InputObject,

    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$NoTypeInformation
  )

  $outPath = Resolve-LcPath -Path $Path
  $parent = Split-Path -Parent $outPath

  if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  $params = @{
    Path              = $outPath
    Force             = $true
    Encoding          = 'UTF8'
  }

  if ($NoTypeInformation) {
    $params['NoTypeInformation'] = $true
  }

  $InputObject | Export-Csv @params
  return $outPath
}
