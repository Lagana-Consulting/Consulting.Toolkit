function Export-AdCsvSafeWithSchema {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $InputObject,
        [Parameter(Mandatory)][string]$Path,
        [switch]$Force,
        [switch]$AllowEmpty
    )

    begin {
        $items = New-Object System.Collections.Generic.List[object]
    }

    process {
        if ($null -ne $InputObject) {
            $items.Add($InputObject)
        }
    }

    end {
        $schemaName = Resolve-AdSchemaNameForCsv -Path $Path
        $data = @($items.ToArray())

        if ($schemaName) {
            $data | Export-AdCsvSafe -Path $Path -SchemaName $schemaName -Force:$Force -AllowEmpty:$AllowEmpty
        } else {
            # fallback: still export, just no schema ordering
            $data | Export-AdCsvSafe -Path $Path -Force:$Force -AllowEmpty:$AllowEmpty
        }
    }
}
