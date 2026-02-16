function New-SATCsv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Headers
    )

    $headerLine = ($Headers -join ',')
    Set-Content -Path $Path -Value $headerLine
}
