function Invoke-SATPackageEvidence {
    [CmdletBinding()]
    param (
        [string]$OutputRoot,

        [string]$AssessmentPath
    )

    Set-StrictMode -Version Latest

    if (-not $OutputRoot) {
        $OutputRoot = Get-SATOutputRootInternal
    }

    if (-not (Test-Path $OutputRoot)) {
        New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
    }

    if (-not $AssessmentPath) {
        $latest = Get-ChildItem -Path $OutputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            throw "No assessment folders found in $OutputRoot"
        }
        $AssessmentPath = $latest.FullName
    }

    $logPath = Join-Path $AssessmentPath 'assessment.log'
    $summaryPath = Join-Path $AssessmentPath 'Assessment_Summary.md'

    Write-SATLog -Message "Packaging evidence for $AssessmentPath" -LogPath $logPath

    $excludeDirs = @('.git', 'output')
    $files = Get-ChildItem -Path $AssessmentPath -Recurse -File | Where-Object {
        $rel = $_.FullName.Substring($AssessmentPath.Length).TrimStart('\')
        $first = if ($rel) { $rel.Split('\')[0] } else { '' }
        ($excludeDirs -notcontains $first) -and ($_.Extension -ne '.zip')
    }
    $fileCount = $files.Count
    $hostsCount = 0
    $portsCount = 0
    if (Test-Path (Join-Path $AssessmentPath 'hosts.csv')) {
        $hostsCount = (Import-Csv (Join-Path $AssessmentPath 'hosts.csv')).Count
    }
    if (Test-Path (Join-Path $AssessmentPath 'ports.csv')) {
        $portsCount = (Import-Csv (Join-Path $AssessmentPath 'ports.csv')).Count
    }

    $summary = @(
        "# Assessment Summary",
        "",
        "Assessment Path: $AssessmentPath",
        "Generated: $(Get-Date -Format 's')",
        "",
        "## Artifact Counts",
        "- Files: $fileCount",
        "- Hosts: $hostsCount",
        "- Ports: $portsCount",
        "",
        "## Files"
    )
    $summary += ($files | Select-Object -ExpandProperty FullName | ForEach-Object { "- $_" })

    Set-Content -Path $summaryPath -Value $summary

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $zipPath = Join-Path $OutputRoot ("Evidence_$timestamp.zip")

    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    Compress-Archive -Path $files.FullName -DestinationPath $zipPath
    Write-SATLog -Message "Evidence package created at $zipPath" -LogPath $logPath

    return [pscustomobject]@{
        AssessmentPath = $AssessmentPath
        Scope          = 'Package'
        EvidenceFiles  = @($zipPath)
        FindingIds     = @()
        PackagePath    = $zipPath
    }
}
