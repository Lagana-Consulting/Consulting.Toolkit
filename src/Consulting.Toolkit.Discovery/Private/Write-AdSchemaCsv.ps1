function Write-AdSchemaCsv {
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

  $dir = Resolve-AdPath -Path $SchemasDir
  New-AdDirectory -Path $dir | Out-Null

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
  Write-AdDiscoveryEvent -Kind Csv -Status START -OutputPath $outPath
  $rows | Export-Csv -Path $outPath -NoTypeInformation -Encoding UTF8 -Force
  Write-AdDiscoveryCsvResult -Path $outPath -RowCount @($rows).Count
  return $outPath
}
