function Write-AdLog {
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
  $ts = Get-AdTimestamp -Format Iso

  $line = "{0} [{1}] {2}" -f $ts, $Level, $Message
  Add-Content -Path $logPath -Value $line -Encoding UTF8
}
