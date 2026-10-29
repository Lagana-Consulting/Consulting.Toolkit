function Export-AdCsvSafe {
    [CmdletBinding()]
    param(
        # Data to export. Accepts pipeline input too.
        [Parameter(ValueFromPipeline)]
        [object]$InputObject,

        # Output CSV path
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        # Optional schema; known discovery filenames resolve automatically.
        # Enforces column order and requires every declared property on each row.
        [string]$SchemaName,

        # Writes even when there are no rows (header only when a schema resolves).
        [switch]$AllowEmpty,

        # Overwrite if exists
        [switch]$Force,

        # UTF8 encoding (default). Use Ascii only if you must support very old tooling.
        [ValidateSet('Utf8', 'Ascii')]
        [string]$Encoding = 'Utf8'
    )

    begin {
        # Collect pipeline objects into a list so we can enforce column order / handle empty.
        $items = New-Object System.Collections.Generic.List[object]

        # Resolve + ensure folder exists
        $outPath = $Path
        try {
            # Resolve-AdPath exists in toolkit already (you’ve used it in other functions)
            if (Get-Command Resolve-AdPath -ErrorAction SilentlyContinue) {
                $outPath = Resolve-AdPath -Path $Path
            }
        } catch {
            # fall back to raw path
            $outPath = $Path
        }

        Write-AdDiscoveryEvent -Kind Csv -Status START -OutputPath $outPath
        $dir = Split-Path -Path $outPath -Parent
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
            throw "File already exists: $outPath (use -Force to overwrite)"
        }

        # Known discovery filenames use the same contract as explicit schema exports.
        if (-not $SchemaName -and (Get-Command Resolve-AdSchemaNameForCsv -ErrorAction SilentlyContinue)) {
            $SchemaName = Resolve-AdSchemaNameForCsv -Path $outPath
        }

        # Load schemas only if needed
        $schemaColumns = $null
        if ($SchemaName) {
            if (-not (Get-Command Get-AdSchemaDefinitions -ErrorAction SilentlyContinue)) {
                throw "SchemaName was provided ('$SchemaName') but Get-AdSchemaDefinitions is not available."
            }

            $schemas = Get-AdSchemaDefinitions
            if (-not $schemas.ContainsKey($SchemaName)) {
                $known = ($schemas.Keys | Sort-Object) -join ', '
                throw "Unknown SchemaName '$SchemaName'. Known schemas: $known"
            }

            # Normalize schema columns to strings if schema definitions are objects
            $schemaColumns = @($schemas[$SchemaName])
            if ($schemaColumns -and $schemaColumns[0] -is [object] -and $schemaColumns[0].PSObject.Properties['Column']) {
                $schemaColumns = @($schemaColumns | Select-Object -ExpandProperty Column)
            }
        }

        $enc = if ($Encoding -eq 'Ascii') { 'ASCII' } else { 'UTF8' }
    }

    process {
        if ($null -ne $InputObject) {
            $items.Add($InputObject)
        }
    }

    end {
        # Handle empty output
        if ($items.Count -eq 0) {
            if (-not $AllowEmpty) {
                # Do nothing by default (prevents creating lots of empty files unless you want them)
                return $outPath
            }

            if ($schemaColumns -and $schemaColumns.Count -gt 0) {
                # Write header-only CSV based on schema
                $emptyRow = [ordered]@{}
                foreach ($column in $schemaColumns) { $emptyRow[$column] = $null }
                $headerLine = [pscustomobject]$emptyRow | ConvertTo-Csv -NoTypeInformation | Select-Object -First 1
                Set-Content -LiteralPath $outPath -Value $headerLine -Encoding $enc -Force
                Write-AdDiscoveryCsvResult -Path $outPath -RowCount 0
                return $outPath
            }

            # If AllowEmpty but no schema, write an empty file (0 bytes)
            Set-Content -LiteralPath $outPath -Value @() -Encoding $enc -Force
            Write-AdDiscoveryCsvResult -Path $outPath -RowCount 0
            return $outPath
        }

        # Enforce schema column order if requested
        if ($schemaColumns -and $schemaColumns.Count -gt 0) {
            foreach ($it in $items) {
                $missing = @($schemaColumns | Where-Object { $null -eq $it.PSObject.Properties[$_] })
                if ($missing.Count -gt 0) {
                    throw "Schema '$SchemaName' cannot export '$outPath': row is missing column(s) $($missing -join ', '). Supply explicit null values when a field is unknown."
                }
            }
            $ordered = foreach ($it in $items) {
                $row = [ordered]@{}
                foreach ($c in $schemaColumns) {
                    $p = $it.PSObject.Properties[$c]
                    $row[$c] = if ($null -ne $p) { $p.Value } else { $null }
                }
                [pscustomobject]$row
            }

            $ordered | Export-Csv -LiteralPath $outPath -NoTypeInformation -Encoding $enc -Force
            Write-AdDiscoveryCsvResult -Path $outPath -RowCount $items.Count
            return $outPath
        }

        # Default: export as-is
        $items | Export-Csv -LiteralPath $outPath -NoTypeInformation -Encoding $enc -Force
        Write-AdDiscoveryCsvResult -Path $outPath -RowCount $items.Count
        return $outPath
    }
}
