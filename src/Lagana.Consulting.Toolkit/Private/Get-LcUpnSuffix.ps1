function Get-LcUpnSuffix {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [string]$UserPrincipalName
  )

  if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) { return $null }

  $at = $UserPrincipalName.LastIndexOf('@')
  if ($at -lt 0 -or $at -eq ($UserPrincipalName.Length - 1)) { return $null }

  return $UserPrincipalName.Substring($at + 1).ToLowerInvariant()
}
