function Export-LcAdmtIncludeFileGroups {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object[]]$Groups,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [string]$SourceNameProperty = 'SamAccountName',

    # Optional rename map: key=SourceName, value=hashtable @{ TargetSAM='x'; TargetRDN='x' }
    [hashtable]$RenameMap,

    [ValidateSet('TargetSAM','TargetRDN')]
    [string[]]$RenameColumns = @('TargetSAM'),

    [switch]$Force
  )

  $outPath = Resolve-LcPath -Path $Path
  $parent = Split-Path -Path $outPath -Parent
  if ($parent) { New-LcDirectory -Path $parent | Out-Null }

  $rows = foreach ($g in $Groups) {
    $src = $g.PSObject.Properties[$SourceNameProperty].Value
    $src = if ($null -ne $src) { ([string]$src).Trim() } else { $null }
    if ([string]::IsNullOrWhiteSpace($src)) { continue }

    $row = [ordered]@{ SourceName = $src }

    if ($RenameMap -and $RenameMap.ContainsKey($src)) {
      $m = $RenameMap[$src]
      foreach ($col in $RenameColumns) {
        if ($m -is [hashtable] -and $m.ContainsKey($col)) { $row[$col] = [string]$m[$col] } else { $row[$col] = $null }
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
