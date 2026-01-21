function Export-LcSchemas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SchemasDir,

        [string[]]$Include
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

        $colDefs = $defs[$name]
        if (-not $colDefs -or $colDefs.Count -eq 0) { continue }

        $outPath = Write-LcSchemaCsv -SchemaName $name -ColumnDefinitions $colDefs -SchemasDir $SchemasDir
        $written += $outPath
    }

    return $written
}
