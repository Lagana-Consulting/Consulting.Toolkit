function Invoke-SATNucleiAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RawJsonlPath,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$AssessmentPath,
        [string]$OutputRoot,
        [string]$SnapshotTimestamp,
        [string]$ConfigRoot
    )

    Set-StrictMode -Version Latest

    if (-not (Test-Path $RawJsonlPath)) {
        throw "RawJsonlPath not found: $RawJsonlPath"
    }

    if (-not $AssessmentPath) {
        $AssessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    }

    if (-not $SnapshotTimestamp) {
        $SnapshotTimestamp = (Get-Date -Format 'yyyyMMddHHmmss')
    }

    $logsDir = Join-Path $AssessmentPath 'Logs'
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $logPath = Join-Path $logsDir 'RunLog.txt'
    Write-SATLog -Message "Invoke-SATNucleiAnalysis started. Profile=$Profile" -LogPath $logPath

    $evidenceRoot = Join-Path $AssessmentPath 'Evidence'
    $nucleiDir = Join-Path $evidenceRoot 'Nuclei'
    if (-not (Test-Path $nucleiDir)) { New-Item -ItemType Directory -Path $nucleiDir -Force | Out-Null }

    $normalizedCsv = Join-Path $nucleiDir ("nuclei-normalized-{0}.csv" -f $SnapshotTimestamp)

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $ConfigRoot) {
        $ConfigRoot = Join-Path $moduleRoot 'config'
    }

    $severityMapPath = Join-Path $ConfigRoot 'severity_map.json'
    $severityMap = @{
        Informational = 0
        Low           = 1
        Medium        = 2
        High          = 3
        Critical      = 4
    }

    if (Test-Path $severityMapPath) {
        $map = Get-Content -Path $severityMapPath -Raw | ConvertFrom-Json
        foreach ($key in $map.PSObject.Properties.Name) {
            $severityMap[$key] = [int]$map.$key
        }
    }

    function New-Finding {
        param (
            [string]$FindingId,
            [string]$Category,
            [string]$Title,
            [string]$Severity,
            [string]$Asset,
            [string]$Domain,
            [int]$EvidenceCount,
            [string]$EvidenceSource,
            [string]$EvidenceRef,
            [string]$Recommendation,
            [string]$PolicyRef,
            [string]$Profile,
            [string]$Tool
        )

        $riskScore = 0
        if ($Severity -and $severityMap.ContainsKey($Severity)) {
            $riskScore = [int]$severityMap[$Severity]
        }

        [pscustomobject]@{
            FindingId      = $FindingId
            Category       = $Category
            Title          = $Title
            Severity       = $Severity
            RiskScore      = $riskScore
            Asset          = $Asset
            Domain         = $Domain
            EvidenceCount  = $EvidenceCount
            EvidenceSource = $EvidenceSource
            EvidenceRef    = $EvidenceRef
            Recommendation = $Recommendation
            PolicyRef      = $PolicyRef
            Profile        = $Profile
            Tool           = $Tool
            Timestamp      = (Get-Date -Format 's')
        }
    }

    function Add-EvidenceIndex {
        param (
            [System.Collections.Generic.List[object]]$Index,
            [string]$FindingId,
            [string]$EvidencePath,
            [string]$Domain,
            [string]$Notes
        )

        $fileName = Split-Path $EvidencePath -Leaf
        $ext = [System.IO.Path]::GetExtension($fileName).TrimStart('.').ToLowerInvariant()
        $type = if ($ext) { $ext } else { 'unknown' }

        $Index.Add([pscustomobject]@{
                FindingId    = $FindingId
                EvidenceFile = $fileName
                EvidenceType = $type
                Domain       = $Domain
                Notes        = $Notes
            })
    }

    # Parse JSONL
    $rows = New-Object System.Collections.Generic.List[object]
    Get-Content -Path $RawJsonlPath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        try {
            $o = $line | ConvertFrom-Json

            $templateId = $null
            if ($o.PSObject.Properties['template-id']) { $templateId = $o.'template-id' }
            elseif ($o.PSObject.Properties['templateID']) { $templateId = $o.templateID }

            $severity = $null
            if ($o.PSObject.Properties['info'] -and $o.info.PSObject.Properties['severity']) {
                $severity = [string]$o.info.severity
            }

            $rows.Add([pscustomobject]@{
                    TemplateId  = [string]$templateId
                    Name        = if ($o.info -and $o.info.name) { [string]$o.info.name } else { $null }
                    SeverityRaw = $severity
                    Host        = if ($o.host) { [string]$o.host } else { $null }
                    MatchedAt   = if ($o.'matched-at') { [string]$o.'matched-at' } else { $null }
                    Type        = if ($o.type) { [string]$o.type } else { $null }
                    Matcher     = if ($o.matcher) { [string]$o.matcher } else { $null }
                    Extracted   = if ($o.extracted_results) { ($o.extracted_results -join '; ') } else { $null }
                    Timestamp   = if ($o.timestamp) { [string]$o.timestamp } else { $null }
                    Reference   = if ($o.info -and $o.info.reference) { ($o.info.reference -join '; ') } else { $null }
                    Tags        = if ($o.info -and $o.info.tags) { [string]$o.info.tags } else { $null }
                })
        } catch {
            # ignore malformed lines; keep it resilient
        }
    }

    if ($rows.Count -gt 0) {
        $rows | Export-Csv -Path $normalizedCsv -NoTypeInformation -Encoding UTF8
    } else {
        # still create the file for consistency
        @() | Export-Csv -Path $normalizedCsv -NoTypeInformation -Encoding UTF8
    }

    # Convert to SAT findings: group by TemplateId + Severity
    $severityMapText = @{
        'info'     = 'Informational'
        'low'      = 'Low'
        'medium'   = 'Medium'
        'high'     = 'High'
        'critical' = 'Critical'
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $evidenceIndex = New-Object System.Collections.Generic.List[object]

    # Evidence index entry
    Add-EvidenceIndex -Index $evidenceIndex `
        -FindingId 'NUCLEI-INDEX' `
        -EvidencePath $normalizedCsv `
        -Domain 'All' `
        -Notes 'Normalized Nuclei results (grouped into findings by template)'

    $grouped = $rows | Group-Object -Property TemplateId
    foreach ($g in $grouped) {
        if (-not $g.Name) { continue }

        $sample = $g.Group | Select-Object -First 1
        $sevKey = if ($sample.SeverityRaw) { $sample.SeverityRaw.ToLowerInvariant() } else { 'info' }
        $sev = if ($severityMapText.ContainsKey($sevKey)) { $severityMapText[$sevKey] } else { 'Informational' }

        $title = if ($sample.Name) { $sample.Name } else { "Nuclei finding: $($g.Name)" }

        $asset = if ($sample.Host) { [string]$sample.Host } else { 'Targets' }

        $findings.Add((
                New-Finding -FindingId ("NUC-{0}" -f $g.Name) `
                    -Category 'Vulnerability' `
                    -Title $title `
                    -Severity $sev `
                    -Asset $asset `
                    -Domain 'All' `
                    -EvidenceCount ([int]$g.Count) `
                    -EvidenceSource 'Nuclei' `
                    -EvidenceRef (Split-Path $normalizedCsv -Leaf) `
                    -Recommendation 'Validate the finding, confirm exposure, and remediate per vendor guidance/change control.' `
                    -PolicyRef 'Client vulnerability management policy' `
                    -Profile $Profile `
                    -Tool 'Identity.Security.Assessment.Toolkit'
            ))
    }

    Export-SATFindings -AssessmentPath $AssessmentPath -Findings $findings -EvidenceIndex $evidenceIndex -Scope 'Nuclei' | Out-Null

    Write-SATLog -Message "Invoke-SATNucleiAnalysis completed. OutputPath=$AssessmentPath" -LogPath $logPath
    return [pscustomobject]@{
        AssessmentPath = $AssessmentPath
        Scope          = 'Nuclei'
        EvidenceFiles  = @($normalizedCsv)
        FindingIds     = @($findings | Select-Object -ExpandProperty FindingId)
        Findings       = @($findings)
    }
}
