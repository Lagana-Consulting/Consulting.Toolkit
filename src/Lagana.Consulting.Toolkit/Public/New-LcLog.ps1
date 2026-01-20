function New-LcLog {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Folder,

    [string]$Prefix = 'lc-toolkit'
  )

  $folderPath = Resolve-LcPath -Path $Folder
  if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory -Force -Path $folderPath | Out-Null
  }

  $ts = Get-LcTimestamp -Format File
  $logPath = Join-Path $folderPath "$Prefix-$ts.log"

  # Create empty file
  New-Item -ItemType File -Force -Path $logPath | Out-Null
  return $logPath
}
