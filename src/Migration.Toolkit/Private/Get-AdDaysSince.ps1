function Get-AdDaysSince {
  [CmdletBinding()]
  param(
    [AllowNull()]
    $DateUtc,

    $Now = (Get-Date).ToUniversalTime()
  )

  if ($null -eq $DateUtc) { return $null }

  $n = if ($Now) { $Now.ToUniversalTime() } else { (Get-Date).ToUniversalTime() }
  $d = $DateUtc.ToUniversalTime()

  # Avoid negative days due to clock skew
  $days = ($n - $d).TotalDays
  if ($days -lt 0) { $days = 0 }

  return [int][math]::Floor($days)
}
