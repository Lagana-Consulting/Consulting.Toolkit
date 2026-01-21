function Export-LcSchemas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SchemasDir,

        [string[]]$Include,

        [hashtable]$Descriptions
    )

    if (-not (Get-Command Get-LcSchemaDefinitions -ErrorAction SilentlyContinue)) {
        throw "Get-LcSchemaDefinitions is not available. Import the Lagana.Consulting.Toolkit module."
    }
    if (-not (Get-Command Write-LcSchemaCsv -ErrorAction SilentlyContinue)) {
        throw "Write-LcSchemaCsv is not available. Import the Lagana.Consulting.Toolkit module."
    }

    $defs = Get-LcSchemaDefinitions
    if (-not $defs -or $defs.Keys.Count -eq 0) {
        throw "Get-LcSchemaDefinitions returned no schemas."
    }

    $names = if ($Include -and $Include.Count -gt 0) { $Include } else { $defs.Keys }

    $written = @()
    foreach ($name in $names) {
        if (-not $defs.ContainsKey($name)) { continue }

        $cols = $defs[$name]
        if (-not $cols -or $cols.Count -eq 0) { continue }

        $desc = $null
        if ($Descriptions -and $Descriptions.ContainsKey($name)) {
            $desc = [string]$Descriptions[$name]
        }

        $outPath = Write-LcSchemaCsv -SchemaName $name -Columns $cols -SchemasDir $SchemasDir -Description $desc
        $written += $outPath
    }

    return $written
}
