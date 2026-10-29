function ConvertTo-AdAssessmentBoolean {
    param([AllowNull()][object]$Value, [string]$Field = 'Boolean value')
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    switch (([string]$Value).Trim().ToLowerInvariant()) {
        { $_ -in @('true', '1', 'yes', 'y') } { return $true }
        { $_ -in @('false', '0', 'no', 'n') } { return $false }
        default { throw "$Field contains an invalid Boolean value: '$Value'." }
    }
}

function ConvertTo-AdAssessmentInteger {
    param([AllowNull()][object]$Value, [string]$Field = 'Integer value')
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $number = 0
    if (-not [int]::TryParse(([string]$Value).Trim(), [Globalization.NumberStyles]::Integer,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        throw "$Field contains an invalid integer value: '$Value'."
    }
    return $number
}

function ConvertTo-AdAssessmentUtcDate {
    param([AllowNull()][object]$Value, [string]$Field = 'Date value')
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    $date = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeLocal, [ref]$date)) {
        throw "$Field contains an invalid date value: '$Value'. Use an ISO 8601 timestamp with a UTC offset."
    }
    return $date.UtcDateTime
}

function Get-AdAssessmentEncryptionState {
    param([AllowNull()][string]$EncryptionTypes)
    $types = @($EncryptionTypes -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $hasAes = $types -contains 'AES128_HMAC_SHA1' -or $types -contains 'AES256_HMAC_SHA1'
    $hasRc4 = $types -contains 'RC4_HMAC'
    $hasDes = $types -contains 'DES_CBC_CRC' -or $types -contains 'DES_CBC_MD5'
    [pscustomobject]@{
        Rc4WithoutAes = $hasRc4 -and -not $hasAes
        NoAes = ($hasRc4 -or $hasDes) -and -not $hasAes
    }
}
