function Export-AdCsvSafeWithSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force,
        [switch]$AllowEmpty
    )

    $schemaName = Resolve-AdSchemaNameForCsv -Path $Path

    if ($schemaName) {
        $InputObject | Export-AdCsvSafe -Path $Path -SchemaName $schemaName -Force:$Force -AllowEmpty:$AllowEmpty
    } else {
        # fallback: still export, just no schema ordering
        $InputObject | Export-AdCsvSafe -Path $Path -Force:$Force -AllowEmpty:$AllowEmpty
    }
}
