function Export-AdCsv {
  <#
  .SYNOPSIS
  Exports objects to CSV with automatic directory creation.

  .DESCRIPTION
  Wrapper around Export-Csv with enhanced features:
  - Creates parent directory if it doesn't exist
  - Resolves paths via Resolve-AdPath (handles env vars, UNC paths)
  - UTF-8 encoding by default
  - Returns the output path for logging/chaining

  .PARAMETER InputObject
  Objects to export. Required.

  .PARAMETER Path
  Output CSV file path. Parent directories created automatically.
  Supports environment variables and UNC paths.
  Required.

  .PARAMETER NoTypeInformation
  Suppress type information header in CSV output.

  .EXAMPLE
  $users | Export-AdCsv -Path "C:\Reports\users.csv" -NoTypeInformation

  Exports users to CSV without type header.

  .EXAMPLE
  $outputPath = Export-AdCsv -InputObject $data -Path "%TEMP%\report.csv"
  Write-Host "Saved to: $outputPath"

  Uses environment variable and returns path for confirmation.

  .EXAMPLE
  Export-AdCsv -InputObject $groups -Path "\\server\share\reports\groups.csv"

  Exports to UNC path (directory auto-created).

  .INPUTS
  PSObject[]. Objects to export.

  .OUTPUTS
  System.String. Full resolved path to the created CSV file.

  .NOTES
  Use Export-AdCsvSafe for schema-validated exports with column ordering.
  This function is for simple CSV exports without schema enforcement.
  Always uses -Force (overwrites existing files).

  .LINK
  Export-AdCsvSafe
  Resolve-AdPath
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [object[]]$InputObject,

    [Parameter(Mandatory)]
    [string]$Path,

    [switch]$NoTypeInformation
  )

  $outPath = Resolve-AdPath -Path $Path
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
