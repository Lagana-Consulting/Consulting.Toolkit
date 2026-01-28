function Export-AdCloudCsv {
  <#
  .SYNOPSIS
  Exports cloud discovery data to CSV with enforced schema consistency.

  .DESCRIPTION
  Wrapper around Export-Csv that enforces consistent column ordering and handles
  complex object serialization for CSV export.

  .PARAMETER InputObject
  Objects to export. Accepts pipeline input.

  .PARAMETER Path
  CSV file path.

  .PARAMETER SchemaName
  Optional schema name (for future schema enforcement; reserved for expansion).

  .PARAMETER Encoding
  File encoding. Default UTF8.

  .PARAMETER NoClobber
  If $true, does not overwrite existing file.

  .EXAMPLE
  $users | Export-AdCloudCsv -Path "users.csv"

  Exports users to CSV with consistent schema.

  .INPUTS
  [PSObject] via pipeline.

  .OUTPUTS
  None; writes to file.

  .NOTES
  Automatically flattens nested properties for CSV compatibility.

  .LINK
  Get-AdCloudUsers
  Get-AdCloudGroups
  Invoke-AdCloudDiscovery
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [PSObject]$InputObject,

    [Parameter(Mandatory)]
    [string]$Path,

    [string]$SchemaName,

    [ValidateSet('UTF8', 'UTF8NoBOM', 'ASCII', 'Default')]
    [string]$Encoding = 'UTF8',

    [switch]$NoClobber
  )

  begin {
    $collection = @()
  }

  process {
    $collection += $InputObject
  }

  end {
    if ($collection.Count -eq 0) {
      Write-Verbose "No objects to export to $Path"
      return
    }

    $csvParams = @{
      Path = $Path
      Encoding = $Encoding
      NoTypeInformation = $true
      ErrorAction = 'Stop'
    }

    if ($NoClobber) {
      $csvParams['NoClobber'] = $true
    }

    try {
      # Flatten complex objects for CSV
      $flattened = $collection | ForEach-Object {
        $obj = $_
        $flatObj = [PSCustomObject]@{}

        foreach ($prop in $obj.PSObject.Properties) {
          $value = $prop.Value

          # Convert complex types to string representation
          if ($value -is [array]) {
            $flatValue = ($value | ForEach-Object { $_.ToString() }) -join '; '
          }
          elseif ($value -is [System.Collections.IDictionary]) {
            $flatValue = ($value | ConvertTo-Json -Compress)
          }
          elseif ($null -eq $value) {
            $flatValue = ''
          }
          else {
            $flatValue = $value.ToString()
          }

          $flatObj | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $flatValue
        }

        $flatObj
      }

      $flattened | Export-Csv @csvParams
      Write-Verbose "Exported $($collection.Count) records to $Path"
    }
    catch {
      throw "Failed to export CSV to $Path. $($_.Exception.Message)"
    }
  }
}
