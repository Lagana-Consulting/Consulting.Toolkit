function Write-LcSchemaCsv {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SchemaName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [array]$ColumnDefinitions,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SchemasDir
  )

  $dir = Resolve-LcPath -Path $SchemasDir
  New-LcDirectory -Path $dir | Out-Null

  $outPath = Join-Path $dir ("Schema_{0}.csv" -f $SchemaName)

  $rows = foreach ($col in $ColumnDefinitions) {
    if ($col -is [string]) {
      # Legacy: just column name, create minimal row
      [pscustomobject]@{
        Column      = $col
        Type        = ''
        Description = ''
        Example     = ''
        Notes       = ''
      }
    } else {
      # Rich schema object
      [pscustomobject]@{
        Column      = [string]$col.Column
        Type        = [string]$col.Type
        Description = [string]$col.Description
        Example     = [string]$col.Example
        Notes       = [string]$col.Notes
      }
    }
  }

  # Always overwrite
  $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Force
  return $outPath
}
