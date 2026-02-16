function Set-SATOutputRoot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$Persist
    )

    $resolved = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    if ($resolved) {
        $Path = $resolved.Path
    }

    $script:SATOutputRoot = $Path

    if ($Persist) {
        $env:SAT_OUTPUT_ROOT = $Path
    }

    return $script:SATOutputRoot
}
