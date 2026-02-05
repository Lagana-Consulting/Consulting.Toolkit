function Read-AssessmentProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile,

        [string]$ConfigRoot
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $ConfigRoot) {
        $ConfigRoot = Join-Path $moduleRoot 'config'
    }

    $profilePath = Join-Path $ConfigRoot (Join-Path 'profiles' "$Profile.json")

    if (Test-Path $profilePath) {
        try {
            return (Get-Content -Path $profilePath -Raw | ConvertFrom-Json)
        } catch {
            Write-Warning "Failed to parse profile at $profilePath. Using defaults."
        }
    }

    return [pscustomobject]@{
        Name = $Profile
        Nmap = [pscustomobject]@{
            Arguments       = switch ($Profile) {
                'LowImpact' { '-sn' }
                'Standard' { '-sS -sV --top-ports 1000' }
                'Deep' { '-sS -sV -O -p-' }
            }
            RequiresConsent = ($Profile -eq 'Deep')
        }
        Web  = [pscustomobject]@{
            ZapMode         = switch ($Profile) {
                'LowImpact' { 'Passive' }
                'Standard' { 'Passive' }
                'Deep' { 'Active' }
            }
            RequiresConsent = ($Profile -eq 'Deep')
        }
    }
}
