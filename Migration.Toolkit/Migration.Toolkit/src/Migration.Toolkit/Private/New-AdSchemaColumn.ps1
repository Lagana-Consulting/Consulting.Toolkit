function New-AdSchemaColumn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Column,

        [string]$Type = 'string',

        [string]$Description = '',

        [string]$Example = '',

        [string]$Notes = ''
    )

    return [pscustomobject]@{
        Column      = $Column
        Type        = $Type
        Description = $Description
        Example     = $Example
        Notes       = $Notes
    }
}
