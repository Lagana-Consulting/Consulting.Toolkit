function New-AdmtPreparationReport {
    <#
    .SYNOPSIS
    Create an ADMT preparation report object and optional CSV/JSON files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'Target')]
        [string]$Role,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Rows,

        [string]$OutputRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $timestamp = Get-AdmtPreparationTimestamp
    $csvPath = $null
    $jsonPath = $null
    $rowsArray = @($Rows)

    if ($OutputRoot) {
        if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
        }

        $csvPath = Join-Path $OutputRoot "ADMT__Preparation__${Role}__Summary__$timestamp.csv"
        $jsonPath = Join-Path $OutputRoot "ADMT__Preparation__${Role}__Summary__$timestamp.json"

        $rowsArray | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Force
        [pscustomobject]@{
            GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            ComputerName   = $env:COMPUTERNAME
            Role           = $Role
            Rows           = $rowsArray
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    }

    return [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Role         = $Role
        CsvPath      = $csvPath
        JsonPath     = $jsonPath
        Rows         = $rowsArray
        PassCount    = @($rowsArray | Where-Object { $_.Status -eq 'Pass' }).Count
        WarningCount = @($rowsArray | Where-Object { $_.Status -in @('Warn', 'Manual') }).Count
        FailureCount = @($rowsArray | Where-Object { $_.Status -eq 'Fail' }).Count
    }
}
