function Get-LcComputerIsServer {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [string]$OperatingSystem
  )

  if ([string]::IsNullOrWhiteSpace($OperatingSystem)) { return $false }

  # Simple and practical: most server OS strings contain "Server"
  return ($OperatingSystem -match 'Server')
}
