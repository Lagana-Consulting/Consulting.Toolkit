function Write-LcSchemaCsv {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SchemaName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Columns,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SchemasDir,

    [string]$Description
  )

  $dir = Resolve-LcPath -Path $SchemasDir
  New-LcDirectory -Path $dir | Out-Null

  $outPath = Join-Path $dir ("{0}.schema.csv" -f $SchemaName)

  $rows = foreach ($c in $Columns) {
    [pscustomobject]@{
      ColumnName  = $c
      Description = $Description
    }
  }

  # Always overwrite
  $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Force
  return $outPath
}
