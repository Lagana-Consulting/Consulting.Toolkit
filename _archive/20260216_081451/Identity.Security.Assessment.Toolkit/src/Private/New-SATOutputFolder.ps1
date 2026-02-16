function New-SATOutputFolder {
    [CmdletBinding()]
    param (
        [string]$OutputRoot
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $OutputRoot) {
        $OutputRoot = Get-SATOutputRootInternal
    }

    if (-not (Test-Path $OutputRoot)) {
        New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $assessmentPath = Join-Path $OutputRoot $timestamp
    New-Item -Path $assessmentPath -ItemType Directory -Force | Out-Null

    return $assessmentPath
}
