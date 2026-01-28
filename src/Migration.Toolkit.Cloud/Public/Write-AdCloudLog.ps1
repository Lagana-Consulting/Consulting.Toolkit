function Write-AdCloudLog {
  <#
  .SYNOPSIS
  Writes timestamped log entry to cloud discovery log file.

  .DESCRIPTION
  Appends a timestamped message to the log file created by New-AdCloudLog.
  Also writes to verbose stream for real-time feedback.

  .PARAMETER Path
  Path to log file (from New-AdCloudLog).

  .PARAMETER Message
  Message text to log.

  .PARAMETER Level
  Log level: 'Info', 'Warning', 'Error'. Default 'Info'.

  .EXAMPLE
  Write-AdCloudLog -Path $logPath -Message "Completed user discovery" -Level Info

  Logs an info message.

  .EXAMPLE
  Write-AdCloudLog -Path $logPath -Message "Connection failed" -Level Error

  Logs an error message.

  .INPUTS
  None.

  .OUTPUTS
  None.

  .LINK
  New-AdCloudLog
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Message,

    [ValidateSet('Info', 'Warning', 'Error')]
    [string]$Level = 'Info'
  )

  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $logEntry = "[$timestamp] [$Level] $Message"

  try {
    Add-Content -Path $Path -Value $logEntry -ErrorAction Stop
    Write-Verbose $logEntry
  }
  catch {
    Write-Warning "Failed to write to log: $_"
  }
}
