function ConvertTo-AdComputerStatusBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes', 'y')) { return $true }
    if ($text -in @('false', '0', 'no', 'n')) { return $false }
    return $Default
}

function ConvertTo-AdComputerStatusNullableInt {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $parsed = 0
    if ([int]::TryParse(([string]$Value).Trim(), [ref]$parsed)) {
        return $parsed
    }

    return $null
}
