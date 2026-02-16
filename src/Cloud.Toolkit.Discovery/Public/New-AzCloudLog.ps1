function New-AzCloudLog {
  <#
  .SYNOPSIS
  Creates a new cloud discovery log file.

  .DESCRIPTION
  Initializes a timestamped log file for discovery output. Returns the path for use with Write-AzCloudLog.

  .PARAMETER Folder
  Folder path for log file. Will be created if missing.

  .PARAMETER Prefix
  Log file name prefix. Default 'cloud-discovery'.

  .EXAMPLE
  $logPath = New-AzCloudLog -Folder "C:\Reports" -Prefix "entra"

  Creates timestamped log file like "C:\Reports\entra__20260128-120000.log"

  .INPUTS
  None.

  .OUTPUTS
  [String] Path to created log file.

  .LINK
  Write-AzCloudLog
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Folder,

    [string]$Prefix = 'cloud-discovery'
  )

  if (-not (Test-Path $Folder)) {
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
  }

  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $logFile = Join-Path $Folder "$($Prefix)__$timestamp.log"

  New-Item -ItemType File -Path $logFile -Force | Out-Null
  return $logFile
}
