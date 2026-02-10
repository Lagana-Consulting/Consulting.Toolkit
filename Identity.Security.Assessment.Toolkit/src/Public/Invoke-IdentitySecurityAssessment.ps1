function Invoke-IdentitySecurityAssessment {
    [CmdletBinding()]
    param (
        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string[]]$Targets,

        [string[]]$Urls,

        [switch]$ADSnapshot,

        [string]$AzureHoundInputPath,

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

    if ($AzureHoundInputPath) {
        $existingAssessmentPath = $results | Select-Object -ExpandProperty AssessmentPath -First 1
        $results.Add((Invoke-SATAzureHoundAnalysis -InputPath $AzureHoundInputPath -Profile $Profile -AssessmentPath $existingAssessmentPath -OutputRoot $OutputRoot))
    }

    if ($Urls) {
        $results.Add((Invoke-SATWebScan -Urls $Urls -Profile $Profile -OutputRoot $OutputRoot -IUnderstandThisIsIntrusive:$IUnderstandThisIsIntrusive))
    }

    if ($PackageEvidence) {
        $results.Add((Invoke-SATPackageEvidence -OutputRoot $OutputRoot))
    }

    $resultsArray = @($results.ToArray())
    $assessmentPath = $resultsArray | Select-Object -ExpandProperty AssessmentPath -First 1
    $scopes = @($resultsArray | Select-Object -ExpandProperty Scope | Sort-Object -Unique)

    $evidenceFiles = @(
        $resultsArray |
        ForEach-Object {
            if ($_.PSObject.Properties['EvidenceFiles'] -and $null -ne $_.EvidenceFiles) {
                @($_.EvidenceFiles)
            }
        } |
        Where-Object { $_ }
    )

    $findingIds = @(
        $resultsArray |
        ForEach-Object {
            if ($_.PSObject.Properties['FindingIds'] -and $null -ne $_.FindingIds) {
                @($_.FindingIds)
            }
        } |
        Where-Object { $_ }
    )

    return [pscustomobject]@{
        Results        = $resultsArray
        AssessmentPath = $assessmentPath
        Scopes         = $scopes
        EvidenceFiles  = $evidenceFiles
        FindingIds     = $findingIds
    }
}
