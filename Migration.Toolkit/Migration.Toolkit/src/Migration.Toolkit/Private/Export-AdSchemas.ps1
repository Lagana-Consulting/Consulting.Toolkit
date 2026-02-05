function Export-AdSchemas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SchemasDir,

        [string[]]$Include
    )

    if (-not (Get-Command Get-AdSchemaDefinitions -ErrorAction SilentlyContinue)) {
        throw "Get-AdSchemaDefinitions is not available. Import the Migration.Toolkit module."
    }
    if (-not (Get-Command Write-AdSchemaCsv -ErrorAction SilentlyContinue)) {
        throw "Write-AdSchemaCsv is not available. Import the Migration.Toolkit module."
    }

    $defs = Get-AdSchemaDefinitions
    if (-not $defs -or $defs.Keys.Count -eq 0) {
        throw "Get-AdSchemaDefinitions returned no schemas."
    }

    $names = if ($Include -and $Include.Count -gt 0) { $Include } else { $defs.Keys }

    $written = @()
    foreach ($name in $names) {
        if (-not $defs.ContainsKey($name)) { continue }

        $colDefs = $defs[$name]
        if (-not $colDefs -or $colDefs.Count -eq 0) { continue }

        $outPath = Write-AdSchemaCsv -SchemaName $name -ColumnDefinitions $colDefs -SchemasDir $SchemasDir
        $written += $outPath
    }

    return $written
}
