function Get-LcEncryptionRisk {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [object]$EncryptionTypeValue
  )

  $types = Convert-LcEncryptionTypes -EncryptionTypeValue $EncryptionTypeValue

  if (-not $types -or $types.Count -eq 0) {
    # Not set often means "defaults", but defaults vary. Keep neutral.
    return 'Unknown'
  }

  $hasAes = ($types -contains 'AES128_HMAC_SHA1' -or $types -contains 'AES256_HMAC_SHA1')
  $hasRc4 = ($types -contains 'RC4_HMAC')
  $hasDes = ($types -contains 'DES_CBC_CRC' -or $types -contains 'DES_CBC_MD5')

  if ($hasDes) { return 'High' }      # DES is legacy/weak
  if ($hasRc4 -and -not $hasAes) { return 'Medium' }  # RC4 only
  if ($hasAes) { return 'Low' }

  return 'Unknown'
}
