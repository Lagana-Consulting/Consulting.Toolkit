function Write-AdLog {
  <#
  .SYNOPSIS
  Writes a timestamped log entry to a log file.

  .DESCRIPTION
  Appends a formatted log entry to the specified log file with timestamp and severity level.
  Log format: {ISO-Timestamp} [{Level}] {Message}
  File is created if it doesn't exist.

  .PARAMETER Message
  The log message to write.

  .PARAMETER Path
  Full path to the log file. Typically obtained from New-AdLog.
  Supports environment variables and UNC paths via Resolve-AdPath.

  .PARAMETER Level
  Severity level of the log entry. Valid values: INFO, WARN, ERROR, DEBUG.
  Default is INFO.

  .EXAMPLE
  Write-AdLog -Path "C:\Logs\migration.log" -Message "Starting AD discovery" -Level INFO

  Writes an INFO level log entry.

  .EXAMPLE
  $log = New-AdLog -Folder "C:\Logs" -Prefix "admt"
  Write-AdLog -Path $log -Message "Trust validation failed" -Level ERROR
  Write-AdLog -Path $log -Message "Retry attempt 1" -Level WARN

  Creates log file and writes multiple entries with different severity levels.

  .EXAMPLE
  try {
    Get-ADForest
  } catch {
    Write-AdLog -Path $logFile -Message "Forest query failed: $($_.Exception.Message)" -Level ERROR
  }

  Logs an exception with ERROR level.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  None. Writes to file only.

  .NOTES
  Uses UTF-8 encoding. Timestamp format is ISO 8601.

  .LINK
  New-AdLog
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Message,

    [Parameter(Mandatory)]
    [string]$Path,

    [ValidateSet('INFO','WARN','ERROR','DEBUG')]
    [string]$Level = 'INFO'
  )

  $logPath = Resolve-AdPath -Path $Path
  $context = Get-Variable -Name adDiscoveryLogContext -ValueOnly -ErrorAction SilentlyContinue
  if ($context -and $context.LogPath -eq $logPath) {
    # Legacy collector warnings indicate incomplete coverage, rather than an
    # empty successful dataset. Retry notices use explicit RETRY events instead.
    Write-AdDiscoveryEvent -Context $context -Status $Level -Message $Message -MarkIncomplete:($Level -in @('WARN', 'ERROR'))
    return
  }
  $ts = Get-AdTimestamp -Format Iso

  $line = "{0} [{1}] {2}" -f $ts, $Level, $Message
  Add-Content -Path $logPath -Value $line -Encoding UTF8
}
