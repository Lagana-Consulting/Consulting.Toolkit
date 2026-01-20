function Convert-LcEncryptionTypes {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [object]$EncryptionTypeValue
  )

  if ($null -eq $EncryptionTypeValue -or [string]::IsNullOrWhiteSpace([string]$EncryptionTypeValue)) {
    return @()
  }

  [int]$v = 0
  try { $v = [int]$EncryptionTypeValue } catch { return @() }

  $types = New-Object System.Collections.Generic.List[string]

  # Bits per Microsoft convention (common)
  if (($v -band 0x01) -ne 0) { $types.Add('DES_CBC_CRC') }
  if (($v -band 0x02) -ne 0) { $types.Add('DES_CBC_MD5') }
  if (($v -band 0x04) -ne 0) { $types.Add('RC4_HMAC') }
  if (($v -band 0x08) -ne 0) { $types.Add('AES128_HMAC_SHA1') }
  if (($v -band 0x10) -ne 0) { $types.Add('AES256_HMAC_SHA1') }

  # Some environments may show this bit; treat as info
  if (($v -band 0x20) -ne 0) { $types.Add('FAST_SUPPORTED') }

  return $types.ToArray()
}
