function Invoke-IdentitySecurityAssessment {
    [CmdletBinding()]
    param (
        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string[]]$Targets,

        [string[]]$Urls,

        [switch]$ADSnapshot,

        [string]$OutputRoot,

        [switch]$PackageEvidence,

        [switch]$IUnderstandThisIsIntrusive
    )

    Set-StrictMode -Version Latest

    Write-Verbose 'Starting Identity Security Assessment'

    $results = New-Object System.Collections.Generic.List[object]

    if ($Targets) {
        $results.Add((Invoke-SATDiscovery -Targets $Targets -Profile $Profile -OutputRoot $OutputRoot -IUnderstandThisIsIntrusive:$IUnderstandThisIsIntrusive))
    }

    if ($ADSnapshot) {
        $results.Add((Invoke-SATADSnapshot -Profile $Profile -OutputRoot $OutputRoot -IUnderstandThisIsIntrusive:$IUnderstandThisIsIntrusive))
    }

    if ($Urls) {
        $results.Add((Invoke-SATWebScan -Urls $Urls -Profile $Profile -OutputRoot $OutputRoot -IUnderstandThisIsIntrusive:$IUnderstandThisIsIntrusive))
    }

    if ($PackageEvidence) {
        $results.Add((Invoke-SATPackageEvidence -OutputRoot $OutputRoot))
    }

    return [pscustomobject]@{
        Results        = @($results)
        AssessmentPath = ($results | Select-Object -ExpandProperty AssessmentPath -First 1)
        Scopes         = ($results | Select-Object -ExpandProperty Scope | Sort-Object -Unique)
        EvidenceFiles  = ($results | ForEach-Object { $_.EvidenceFiles } | Where-Object { $_ })
        FindingIds     = ($results | ForEach-Object { $_.FindingIds } | Where-Object { $_ })
    }
}
