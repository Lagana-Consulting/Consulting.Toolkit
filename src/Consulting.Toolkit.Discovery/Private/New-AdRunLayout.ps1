function New-AdRunLayout {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputRoot,

    [string]$Prefix = 'ADOnly',

    [datetime]$Now = (Get-Date),

    [switch]$CreateLog,

    [string]$LogPrefix = 'discovery'
  )

  # Normalize / ensure output root exists
  $root = Resolve-AdPath -Path $OutputRoot
  New-AdDirectory -Path $root | Out-Null

  # Run folder name: <Prefix>_<yyyyMMdd-HHmmss>
  $stamp = $Now.ToString('yyyyMMdd-HHmmss')
  $runFolderName = "{0}_{1}" -f $Prefix, $stamp
  $runRoot = Join-Path $root $runFolderName
  New-AdDirectory -Path $runRoot | Out-Null

  # Standard subfolders
  $schemasDir = Join-Path $runRoot '00_schemas'
  New-AdDirectory -Path $schemasDir | Out-Null

  $logsDir = Join-Path $runRoot '90_logs'
  New-AdDirectory -Path $logsDir | Out-Null

  $logPath = $null
  if ($CreateLog) {
    $logPath = New-AdLog -Folder $logsDir -Prefix $LogPrefix
    Write-AdLog -Path $logPath -Level INFO -Message ("Run layout created. RunRoot={0}" -f $runRoot)
  }

  [pscustomobject]@{
    OutputRoot = $root
    RunRoot    = $runRoot
    SchemasDir = $schemasDir
    LogsDir    = $logsDir
    LogPath    = $logPath
    Prefix     = $Prefix
    Stamp      = $stamp
    Now        = $Now
  }
}
