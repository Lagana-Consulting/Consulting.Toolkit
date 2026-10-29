function Get-AdGpoVersionNumber {
    param($Gpo, [ValidateSet('User', 'Computer')][string]$Section)
    $value = $null
    if ($Gpo.PSObject.Properties[$Section] -and $Gpo.$Section -and $Gpo.$Section.PSObject.Properties['DSVersion']) {
        $value = $Gpo.$Section.DSVersion
    } elseif ($Gpo.PSObject.Properties[($Section + 'Version')]) {
        $value = $Gpo.($Section + 'Version')
    }
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { return $null }
    $number = 0
    if (-not [int]::TryParse([string]$value, [ref]$number)) {
        throw "GPO $Section version is not an integer: '$value'."
    }
    return $number
}
