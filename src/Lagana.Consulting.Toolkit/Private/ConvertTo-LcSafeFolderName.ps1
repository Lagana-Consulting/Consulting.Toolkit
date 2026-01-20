function ConvertTo-LcSafeFolderName {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Name
  )

  # Replace invalid filename chars with underscore
  $invalid = [System.IO.Path]::GetInvalidFileNameChars()
  $safe = ($Name.ToCharArray() | ForEach-Object {
    if ($invalid -contains $_) { '_' } else { $_ }
  }) -join ''

  # Also replace dots with underscores to keep folder names consistent
  $safe = $safe -replace '\.', '_'

  # Collapse repeating underscores
  $safe = $safe -replace '_{2,}', '_'

  return $safe.Trim('_')
}
