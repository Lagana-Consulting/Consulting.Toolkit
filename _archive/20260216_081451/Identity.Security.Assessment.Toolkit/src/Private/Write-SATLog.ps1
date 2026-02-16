function Write-SATLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $timestamp = Get-Date -Format 's'
    $line = "[$timestamp] $Message"
    Add-Content -Path $LogPath -Value $line
}
