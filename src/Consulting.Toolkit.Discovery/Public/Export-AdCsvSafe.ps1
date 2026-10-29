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
        $outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($outPath)

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

        $csvEncoding = if ($Encoding -eq 'Ascii') { [System.Text.Encoding]::ASCII } else {
            # Preserve the engine's existing UTF8 BOM convention.
            New-Object System.Text.UTF8Encoding($PSVersionTable.PSVersion.Major -le 5)
        }
        $csvState = @{
            Buffer = New-Object System.Collections.Generic.List[object]
            Columns = $schemaColumns
            TempPath = Join-Path $dir ('.' + [IO.Path]::GetFileName($outPath) + '.' + [guid]::NewGuid().ToString('N') + '.partial')
            HeaderWritten = $false
            RowCount = [long]0
        }
        function Write-AdCsvBuffer {
            param($State, $TextEncoding)
            if ($State.Buffer.Count -eq 0) { return }
            $lines = @($State.Buffer.ToArray() | ConvertTo-Csv -NoTypeInformation -ErrorAction Stop)
            $writer = New-Object System.IO.StreamWriter($State.TempPath, $true, $TextEncoding)
            try {
                $start = if ($State.HeaderWritten) { 1 } else { 0 }
                for ($i = $start; $i -lt $lines.Count; $i++) { $writer.WriteLine($lines[$i]) }
            } finally { $writer.Dispose() }
            $State.HeaderWritten = $true
            $State.Buffer.Clear()
        }
    }

    process {
        if ($null -ne $InputObject) {
            try {
                if ($schemaColumns -and $schemaColumns.Count -gt 0) {
                    $missing = @(foreach ($column in $schemaColumns) {
                        if ($null -eq $InputObject.PSObject.Properties[$column]) { $column }
                    })
                    if ($missing.Count -gt 0) {
                        throw "Schema '$SchemaName' cannot export '$outPath': row is missing column(s) $($missing -join ', '). Supply explicit null values when a field is unknown."
                    }
                }
                if (-not $csvState.Columns) { $csvState.Columns = @($InputObject.PSObject.Properties.Name) }
                $row = [ordered]@{}
                foreach ($column in $csvState.Columns) {
                    $property = $InputObject.PSObject.Properties[$column]
                    $value = if ($null -ne $property) { $property.Value } else { $null }
                    if ($value -is [datetime] -or $value -is [datetimeoffset]) {
                        $value = $value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
                    }
                    $row[$column] = $value
                }
                $csvState.Buffer.Add([pscustomobject]$row)
                $csvState.RowCount++
                if ($csvState.Buffer.Count -ge 256) { Write-AdCsvBuffer $csvState $csvEncoding }
                if (($csvState.RowCount % 10000) -eq 0) {
                    Write-AdDiscoveryEvent -Kind Csv -Status INFO -OutputPath $outPath -RowCount $csvState.RowCount -Details @{ Phase = 'Staging'; Published = $false }
                }
            } catch {
                # No writer remains open between process calls, including on interruption.
                $csvState.Buffer.Clear()
                Remove-Item -LiteralPath $csvState.TempPath -Force -ErrorAction SilentlyContinue
                throw
            }
        }
    }

    end {
        try {
            if ($csvState.RowCount -eq 0) {
                if (-not $AllowEmpty) { return $outPath }
                if ($schemaColumns -and $schemaColumns.Count -gt 0) {
                    $emptyRow = [ordered]@{}
                    foreach ($column in $schemaColumns) { $emptyRow[$column] = $null }
                    $headerLine = [pscustomobject]$emptyRow | ConvertTo-Csv -NoTypeInformation | Select-Object -First 1
                    [IO.File]::WriteAllText($csvState.TempPath, $headerLine + [Environment]::NewLine, $csvEncoding)
                } else {
                    [IO.File]::WriteAllBytes($csvState.TempPath, [byte[]]@())
                }
            } else { Write-AdCsvBuffer $csvState $csvEncoding }

            # Staging in the destination folder permits an atomic rename/replace.
            # Recheck existence so a concurrent writer cannot bypass -Force.
            if ([IO.File]::Exists($outPath)) {
                if (-not $Force) { throw "File already exists: $outPath (use -Force to overwrite)" }
                # Preserve destination metadata/ACLs; fail instead of ignoring
                # metadata errors when the caller lacks replacement permissions.
                [IO.File]::Replace($csvState.TempPath, $outPath, [NullString]::Value, $false)
            } else { [IO.File]::Move($csvState.TempPath, $outPath) }
            Write-AdDiscoveryCsvResult -Path $outPath -RowCount $csvState.RowCount
            return $outPath
        } finally {
            Remove-Item -LiteralPath $csvState.TempPath -Force -ErrorAction SilentlyContinue
        }
    }
}
