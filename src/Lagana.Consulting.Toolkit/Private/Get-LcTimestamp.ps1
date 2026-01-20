function Get-LcTimestamp {
  [CmdletBinding()]
  param(
    [ValidateSet('File','Iso')]
    [string]$Format = 'Iso'
  )

  switch ($Format) {
    'File' { return (Get-Date).ToString('yyyyMMdd-HHmmss') }
    'Iso'  { return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
  }
}
