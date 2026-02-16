function Invoke-SATNetworkVulnAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$AssessmentPath,
        [string]$OutputRoot,
        [string]$ConfigRoot,

        [switch]$IncludeNuclei
    )

    Set-StrictMode -Version Latest

    if (-not $AssessmentPath) {
        $AssessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    }

    $results = New-Object System.Collections.Generic.List[object]

    if ($IncludeNuclei) {
        $scan = Invoke-SATNucleiScan -Targets $Targets -Profile $Profile -AssessmentPath $AssessmentPath -OutputRoot $OutputRoot -ConfigRoot $ConfigRoot
        $results.Add($scan)

        if ($scan.RawJsonl) {
            $analysis = Invoke-SATNucleiAnalysis -RawJsonlPath $scan.RawJsonl -Profile $Profile -AssessmentPath $AssessmentPath -OutputRoot $OutputRoot -SnapshotTimestamp $scan.Timestamp -ConfigRoot $ConfigRoot
            $results.Add($analysis)
        }
    }

    return [pscustomobject]@{
        AssessmentPath = $AssessmentPath
        Scope          = 'NetworkVuln'
        EvidenceFiles  = ($results | ForEach-Object { $_.EvidenceFiles } | Where-Object { $_ })
        FindingIds     = ($results | ForEach-Object { $_.FindingIds } | Where-Object { $_ })
        Results        = @($results)
    }
}
