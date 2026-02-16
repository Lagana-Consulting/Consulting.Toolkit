function Export-SATFindings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$AssessmentPath,

        [array]$Findings,

        [array]$EvidenceIndex,

        [ValidateSet('AD', 'Entra', 'M365', 'BloodHound', 'Nuclei')]
        [string]$Scope = 'AD'
    )

    Set-StrictMode -Version Latest

    $evidenceRoot = Join-Path $AssessmentPath 'Evidence'
    $scopeDir = Join-Path $evidenceRoot $Scope

    if (-not (Test-Path $evidenceRoot)) {
        New-Item -Path $evidenceRoot -ItemType Directory -Force | Out-Null
    }

    if (-not (Test-Path $scopeDir)) {
        New-Item -Path $scopeDir -ItemType Directory -Force | Out-Null
    }

    $findingsPath = Join-Path $scopeDir ("Findings_{0}.csv" -f $Scope)
    $indexPath = Join-Path $scopeDir ("EvidenceIndex_{0}.csv" -f $Scope)

    if ($Findings -and $Findings.Count -gt 0) {
        $Findings | Export-Csv -Path $findingsPath -NoTypeInformation -Encoding UTF8
    } else {
        'FindingId,Category,Title,Severity,RiskScore,Asset,Domain,EvidenceCount,EvidenceSource,EvidenceRef,Recommendation,PolicyRef,Profile,Tool,Timestamp' | Set-Content -Path $findingsPath
    }

    if ($EvidenceIndex -and $EvidenceIndex.Count -gt 0) {
        $EvidenceIndex | Export-Csv -Path $indexPath -NoTypeInformation -Encoding UTF8
    } else {
        'FindingId,EvidenceFile,EvidenceType,Domain,Notes' | Set-Content -Path $indexPath
    }

    return [pscustomobject]@{
        FindingsPath      = $findingsPath
        EvidenceIndexPath = $indexPath
        EvidenceRoot      = $scopeDir
    }
}
