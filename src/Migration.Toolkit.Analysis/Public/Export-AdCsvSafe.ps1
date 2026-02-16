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

    # Optional: Schema name from Get-AdSchemaDefinitions to enforce column order
    [string]$SchemaName,

    # If specified, writes even when there are no rows (header only if SchemaName provided)
    [switch]$AllowEmpty,

    # Overwrite if exists
    [switch]$Force,

    # UTF8 encoding (default). Use Ascii only if you must support very old tooling.
    [ValidateSet('Utf8','Ascii')]
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

    $dir = Split-Path -Path $outPath -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
      throw "File already exists: $outPath (use -Force to overwrite)"
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

      $schemaColumns = @($schemas[$SchemaName])
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
        $headerLine = ($schemaColumns -join ',')
        Set-Content -Path $outPath -Value $headerLine -Encoding $enc -Force
        return $outPath
      }

      # If AllowEmpty but no schema, write an empty file (0 bytes)
      Set-Content -Path $outPath -Value @() -Encoding $enc -Force
      return $outPath
    }

    # Enforce schema column order if requested
    if ($schemaColumns -and $schemaColumns.Count -gt 0) {
      $ordered = foreach ($it in $items) {
        $row = [ordered]@{}
        foreach ($c in $schemaColumns) {
          $p = $it.PSObject.Properties[$c]
          $row[$c] = if ($null -ne $p) { $p.Value } else { $null }
        }
        [pscustomobject]$row
      }

      $ordered | Export-Csv -Path $outPath -NoTypeInformation -Encoding $enc -Force
      return $outPath
    }

    # Default: export as-is
    $items | Export-Csv -Path $outPath -NoTypeInformation -Encoding $enc -Force
    return $outPath
  }
}
