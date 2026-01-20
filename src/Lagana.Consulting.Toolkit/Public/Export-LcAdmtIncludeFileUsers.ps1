function Export-LcAdmtIncludeFileUsers {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object[]]$Users,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    # Property on $Users used as the "SourceName" value (SamAccountName is typical)
    [string]$SourceNameProperty = 'SamAccountName',

    # Optional rename map: key=SourceName, value=hashtable @{ TargetSAM='x'; TargetRDN='x'; TargetUPN='x' }
    [hashtable]$RenameMap,

    # Which rename columns to emit (ADMT supports these for users)
    [ValidateSet('TargetSAM','TargetRDN','TargetUPN')]
    [string[]]$RenameColumns = @('TargetSAM'),

    [switch]$Force
  )

  $outPath = Resolve-LcPath -Path $Path
  $parent = Split-Path -Path $outPath -Parent
  if ($parent) { New-LcDirectory -Path $parent | Out-Null }

  $rows = foreach ($u in $Users) {
    $src = $u.PSObject.Properties[$SourceNameProperty].Value
    $src = if ($null -ne $src) { ([string]$src).Trim() } else { $null }
    if ([string]::IsNullOrWhiteSpace($src)) { continue }

    $row = [ordered]@{ SourceName = $src }

    if ($RenameMap -and $RenameMap.ContainsKey($src)) {
      $m = $RenameMap[$src]
      foreach ($col in $RenameColumns) {
        if ($m -is [hashtable] -and $m.ContainsKey($col)) {
          $row[$col] = [string]$m[$col]
        } else {
          $row[$col] = $null
        }
      }
    } else {
      foreach ($col in $RenameColumns) { $row[$col] = $null }
    }

    [pscustomobject]$row
  }

  if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
    throw "File already exists: $outPath (use -Force to overwrite)"
  }

  $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Force
  return $outPath
}
