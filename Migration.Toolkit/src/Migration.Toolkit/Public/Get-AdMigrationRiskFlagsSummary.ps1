function Get-AdMigrationRiskFlagsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$RiskFlagsData
    )

    # Split flags and group by flag + object class
    $flagRows = foreach ($row in $RiskFlagsData) {
        $flags = $row.Flags -split ';'
        foreach ($flag in $flags) {
            [pscustomobject]@{
                Flag        = $flag.Trim()
                ObjectClass = $row.ObjectClass
            }
        }
    }

    # Group and count
    $flagRows |
    Group-Object -Property Flag, ObjectClass |
    ForEach-Object {
        $parts = $_.Name -split ', '
        [pscustomobject]@{
            Flag        = $parts[0]
            ObjectClass = $parts[1]
            Count       = $_.Count
        }
    } |
    Sort-Object -Property @{Expression = { $_.Count }; Descending = $true }, Flag
}
