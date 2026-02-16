function ConvertFrom-AdFileTime {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [object]$FileTime
  )

  if ($null -eq $FileTime) { return $null }

  try {
    # lastLogonTimestamp can come back as Int64, string, or large integer
    [int64]$ft = [int64]$FileTime
    if ($ft -le 0) { return $null }
    return [DateTime]::FromFileTimeUtc($ft)
  } catch {
    return $null
  }
}
