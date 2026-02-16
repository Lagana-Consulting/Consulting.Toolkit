function Get-SATToolVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Command,

        [string[]]$VersionArgs = @('--version')
    )

    $tool = Get-Command -Name $Command -ErrorAction SilentlyContinue
    if (-not $tool) {
        return $null
    }

    try {
        $output = & $tool.Source @VersionArgs 2>&1
        if ($output) {
            return ($output | Select-Object -First 1)
        }
    } catch {
        return $null
    }

    return $null
}
