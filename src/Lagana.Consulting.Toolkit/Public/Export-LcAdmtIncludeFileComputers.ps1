function Export-LcAdmtIncludeFileComputers {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object[]]$Computers,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    # Typically SamAccountName for computer includes the trailing $, but discovery data may vary
    [string]$SourceNameProperty = 'SamAccountName',

    # Ensure a trailing $ (ADMT often expects computer SAM style). If your source list is "NAME$", keep this on.
    [switch]$EnsureTrailingDollar = $true,

    [switch]$Force
  )

  $outPath = Resolve-LcPath -Path $Path
  $parent = Split-Path -Path $outPath -Parent
  if ($parent) { New-LcDirectory -Path $parent | Out-Null }

  $rows = foreach ($c in $Computers) {
    $src = $c.PSObject.Properties[$SourceNameProperty].Value
    $src = if ($null -ne $src) { ([string]$src).Trim() } else { $null }
    if ([string]::IsNullOrWhiteSpace($src)) { continue }

    if ($EnsureTrailingDollar) {
      if (-not $src.EndsWith('$')) { $src = $src + '$' }
    }

    [pscustomobject]@{ SourceName = $src }
  }

  if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
    throw "File already exists: $outPath (use -Force to overwrite)"
  }

  $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Force
  return $outPath
}
