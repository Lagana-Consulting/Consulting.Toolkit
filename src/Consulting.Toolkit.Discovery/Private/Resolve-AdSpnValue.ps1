function Resolve-AdSpnValue {
    param([Parameter(Mandatory)]$Row)
    $hasCanonical = $null -ne $Row.PSObject.Properties['ServicePrincipalName']
    $hasAlias = $null -ne $Row.PSObject.Properties['SPN']
    if (-not $hasCanonical -and -not $hasAlias) { throw 'SPN rows must contain ServicePrincipalName (or the legacy SPN alias).' }
    $value = if ($hasCanonical) { [string]$Row.ServicePrincipalName } else { [string]$Row.SPN }
    if ([string]::IsNullOrWhiteSpace($value)) { throw 'SPN rows cannot contain a blank service principal name.' }
    if ($hasCanonical -and $hasAlias -and $value -ne [string]$Row.SPN) {
        throw 'ServicePrincipalName and its legacy SPN alias disagree.'
    }
    return $value
}
