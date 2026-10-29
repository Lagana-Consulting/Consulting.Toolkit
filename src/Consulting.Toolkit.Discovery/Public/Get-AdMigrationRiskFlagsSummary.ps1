function Get-AdMigrationRiskFlagsSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$RiskFlagsData
    )

    # Split flags and group by flag + object class
    $flagRows = foreach ($row in $RiskFlagsData) {
        $flags = @($row.Flags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
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
        $flag = $_.Group[0]
        [pscustomobject]@{
            Flag        = $flag.Flag
            ObjectClass = $flag.ObjectClass
            Count       = $_.Count
        }
    } |
    Sort-Object -Property @{Expression = { $_.Count }; Descending = $true }, Flag
}
