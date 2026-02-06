function New-AdLog {
  <#
  .SYNOPSIS
  Creates a new log file with timestamp in specified folder.

  .DESCRIPTION
  Generates a timestamped log file in the specified directory. Creates the directory
  if it doesn't exist. Returns the full path to the created log file for use with
  Write-AdLog.

  .PARAMETER Folder
  Directory path where log file will be created. Will be created if it doesn't exist.
  Supports environment variables and UNC paths via Resolve-AdPath.

  .PARAMETER Prefix
  Optional prefix for the log filename. Default is 'lc-toolkit'.
  Final filename format: {Prefix}-{Timestamp}.log

  .EXAMPLE
  $log = New-AdLog -Folder "C:\Logs"

  Creates a log file in C:\Logs with default prefix (e.g., lc-toolkit-20260128-143022.log)

  .EXAMPLE
  $log = New-AdLog -Folder "C:\AD\Reports" -Prefix "migration"
  Write-AdLog -Path $log -Message "Migration started" -Level INFO

  Creates a log file with custom prefix and writes an entry to it.

  .EXAMPLE
  $log = New-AdLog -Folder "%TEMP%\ADReports" -Prefix "discovery"

  Creates log in expanded TEMP directory with custom prefix.

  .OUTPUTS
  System.String. Full path to the created log file.

  .NOTES
  Uses Get-AdTimestamp for consistent file-safe timestamp formatting.

  .LINK
  Write-AdLog
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Folder,

    [string]$Prefix = 'lc-toolkit'
  )

  $folderPath = Resolve-AdPath -Path $Folder
  if (-not (Test-Path $folderPath)) {
    New-Item -ItemType Directory -Force -Path $folderPath | Out-Null
  }

  $ts = Get-AdTimestamp -Format File
  $logPath = Join-Path $folderPath "$Prefix-$ts.log"

  # Create empty file
  New-Item -ItemType File -Force -Path $logPath | Out-Null
  return $logPath
}
