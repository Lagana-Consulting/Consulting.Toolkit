<#
.SYNOPSIS
Runs the common Migration.Toolkit.Analysis workflow for one or more source discovery runs.

.DESCRIPTION
Imports the local Migration.Toolkit.Analysis module and generates the standard
analysis outputs from current Consulting.Toolkit.Discovery run folders.

For each source run, the script can generate:
- Executive assessment HTML report
- Migration planning HTML report
- Optional comprehensive assessment HTML report

When a target run is also supplied, the script additionally generates a
comparison and readiness report for each source run against that target.

When workspace generation is enabled, the script also creates one shared
analysis workspace by passing every source run plus the optional target run to
`Invoke-AdDiscoveryAnalysis`.

.PARAMETER SourceRunRoot
One or more paths to source discovery run roots produced by
Consulting.Toolkit.Discovery.

.PARAMETER TargetRunRoot
Optional path to the target discovery run root. When provided, comparison and
readiness outputs are also generated.

.PARAMETER OutputRoot
Optional folder where reports and workspace output should be written.
For a single source run, defaults to `<SourceRunRoot>\40_assessment`.
For multiple source runs, defaults to `AnalysisOutputs_<timestamp>` under the
current working directory.

.PARAMETER WorkspaceRoot
Optional explicit path for the analysis workspace. If omitted and workspace
generation is enabled, the script creates `AnalysisWorkspace_<timestamp>`
under `OutputRoot`.

.PARAMETER CustomerName
Optional friendly name used by reports that display customer context.
Default is `Organization`.

.PARAMETER ExecutiveSummaryConfigPath
Optional path to a JSON file with consultant-supplied executive summary
overrides such as migration approach, DNS overlap assessment, and hybrid
identity considerations.

.PARAMETER SkipWorkspace
Skip the Invoke-AdDiscoveryAnalysis workspace step and generate only HTML reports.

.PARAMETER IncludeComprehensiveReport
Also generate the comprehensive assessment report in addition to the lighter
assessment and planning reports.

.EXAMPLE
& .\run-analysis.ps1 `
  -SourceRunRoot "F:\Shared\AD_sourcelab.com_20260423-082040"

Runs the source-only workflow and writes output to:
`F:\Shared\AD_sourcelab.com_20260423-082040\40_assessment`

.EXAMPLE
& .\run-analysis.ps1 `
  -SourceRunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -OutputRoot "F:\Shared\AD_sourcelab.com_20260423-082040\40_assessment" `
  -SkipWorkspace

Generates the standard HTML reports only and skips the analysis workspace.

.EXAMPLE
& .\run-analysis.ps1 `
  -SourceRunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -TargetRunRoot "F:\Shared\AD_targetlab.com_20260423-090000" `
  -CustomerName "Lab"

Generates source/target comparison outputs, readiness checklist, and analysis workspace.

.EXAMPLE
& .\run-analysis.ps1 `
  -SourceRunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -WorkspaceRoot "F:\Shared\AssessmentOutputs\SourcelabWorkspace" `
  -IncludeComprehensiveReport

Writes reports to the default `40_assessment` folder and uses an explicit
workspace path while also producing the comprehensive assessment report.

.EXAMPLE
& .\run-analysis.ps1 `
  -SourceRunRoot @(
    "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723",
    "F:\Versetal\lighthouse\Discovery\AD_lighthouseoptics.local__lighthouseoptical_20260428-141625"
  ) `
  -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
  -OutputRoot "F:\Versetal\AssessmentOutputs" `
  -WorkspaceRoot "F:\Versetal\AnalysisWorkspace_Versetal" `
  -CustomerName "Versetal"

Generates one report set per source run under `F:\Versetal\AssessmentOutputs`
and one shared cross-run workspace under `F:\Versetal\AnalysisWorkspace_Versetal`.

.NOTES
This script is intended to be run directly from PowerShell rather than imported
as a module function.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$SourceRunRoot,

    [string]$TargetRunRoot,

    [string]$OutputRoot,

    [string]$WorkspaceRoot,

    [string]$CustomerName = 'Organization',

    [string]$ExecutiveSummaryConfigPath,

    [switch]$SkipWorkspace,

    [switch]$IncludeComprehensiveReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RunAnalysisLabel {
    param(
        [Parameter(Mandatory)]
        [string]$RunRoot,

        [Parameter(Mandatory)]
        [int]$Index
    )

    $leaf = Split-Path -Path $RunRoot -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        $leaf = "Source$Index"
    }

    $safeLeaf = ($leaf -replace '[^\w\.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeLeaf)) {
        $safeLeaf = "Source$Index"
    }

    return ('source_{0:00}_{1}' -f $Index, $safeLeaf)
}

$SourceRunRoot = @($SourceRunRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($SourceRunRoot.Count -eq 0) {
    throw "Provide at least one SourceRunRoot."
}

foreach ($sourcePath in $SourceRunRoot) {
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Source run root not found: $sourcePath"
    }
}

if ($PSBoundParameters.ContainsKey('TargetRunRoot') -and -not [string]::IsNullOrWhiteSpace($TargetRunRoot)) {
    if (-not (Test-Path -LiteralPath $TargetRunRoot -PathType Container)) {
        throw "Target run root not found: $TargetRunRoot"
    }
} else {
    $TargetRunRoot = $null
}

$moduleRoot = Split-Path -Parent $PSScriptRoot
$moduleManifest = Join-Path $moduleRoot 'Migration.Toolkit.Analysis.psd1'
if (-not (Test-Path -LiteralPath $moduleManifest -PathType Leaf)) {
    throw "Module manifest not found: $moduleManifest"
}

Import-Module $moduleManifest -Force

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$primarySourceRunRoot = $SourceRunRoot[0]

if (-not $OutputRoot) {
    if ($SourceRunRoot.Count -eq 1) {
        $OutputRoot = Join-Path $primarySourceRunRoot '40_assessment'
    } else {
        $OutputRoot = Join-Path (Get-Location).Path "AnalysisOutputs_$timestamp"
    }
}

if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

if (-not $SkipWorkspace -and -not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path $OutputRoot "AnalysisWorkspace_$timestamp"
}

$results = [ordered]@{
    SourceRunRoot = $SourceRunRoot
    SourceRunCount = $SourceRunRoot.Count
    TargetRunRoot = $TargetRunRoot
    OutputRoot    = $OutputRoot
    WorkspaceRoot = $WorkspaceRoot
}

Write-Host "Running AD analysis wrapper..." -ForegroundColor Cyan
foreach ($sourcePath in $SourceRunRoot) {
    Write-Host "  Source: $sourcePath" -ForegroundColor Gray
}
if ($TargetRunRoot) {
    Write-Host "  Target: $TargetRunRoot" -ForegroundColor Gray
}
Write-Host "  Output: $OutputRoot" -ForegroundColor Gray

$reportSets = @()
for ($i = 0; $i -lt $SourceRunRoot.Count; $i++) {
    $currentSourceRunRoot = $SourceRunRoot[$i]
    $sourceLabel = Get-RunAnalysisLabel -RunRoot $currentSourceRunRoot -Index ($i + 1)

    if ($SourceRunRoot.Count -eq 1) {
        $reportOutputRoot = $OutputRoot
    } else {
        $reportOutputRoot = Join-Path $OutputRoot $sourceLabel
        if (-not (Test-Path -LiteralPath $reportOutputRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $reportOutputRoot -Force | Out-Null
        }
    }

    Write-Host ""
    Write-Host "Generating reports for source $($i + 1) of $($SourceRunRoot.Count)..." -ForegroundColor Cyan
    Write-Host "  Source: $currentSourceRunRoot" -ForegroundColor Gray
    if ($SourceRunRoot.Count -gt 1) {
        Write-Host "  Report Output: $reportOutputRoot" -ForegroundColor Gray
    }

    $reportSet = [ordered]@{
        SourceRunRoot = $currentSourceRunRoot
        OutputRoot    = $reportOutputRoot
    }

    $assessmentPath = Join-Path $reportOutputRoot "AD__Assessment__Report__$timestamp.html"
    $planningPath = Join-Path $reportOutputRoot "AD__Migration__Planning__Report__$timestamp.html"

    Write-Host "Generating assessment report..." -ForegroundColor Cyan
    $assessmentParams = @{
        DiscoveryOutputPath = $currentSourceRunRoot
        OutputPath          = $assessmentPath
    }
    if ($TargetRunRoot) {
        $assessmentParams.TargetRunRoot = $TargetRunRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($ExecutiveSummaryConfigPath)) {
        $assessmentParams.ExecutiveSummaryConfigPath = $ExecutiveSummaryConfigPath
    }

    $assessment = New-AdAssessmentReport @assessmentParams
    $reportSet.AssessmentReport = $assessment.ReportPath

    Write-Host "Generating migration planning report..." -ForegroundColor Cyan
    $planning = New-AdMigrationPlanningReport -DiscoveryOutputPath $currentSourceRunRoot -OutputPath $planningPath
    $reportSet.PlanningReport = $planning.ReportPath

    if ($IncludeComprehensiveReport) {
        $comprehensivePath = Join-Path $reportOutputRoot "AD__Comprehensive__Assessment__Report__$timestamp.html"
        Write-Host "Generating comprehensive assessment report..." -ForegroundColor Cyan
        $comprehensive = New-AdComprehensiveAssessmentReport -DiscoveryOutputPath $currentSourceRunRoot -OutputPath $comprehensivePath -CustomerName $CustomerName
        $reportSet.ComprehensiveReport = $comprehensive.Path
    }

    if ($TargetRunRoot) {
        $comparisonPath = Join-Path $reportOutputRoot "AD__Environment__Comparison__Report__$timestamp.html"
        $readinessPath = Join-Path $reportOutputRoot "AD__Migration__Readiness__Checklist__$timestamp.html"

        Write-Host "Generating environment comparison report..." -ForegroundColor Cyan
        $comparison = New-AdEnvironmentComparisonReport `
            -SourceRunRoot $currentSourceRunRoot `
            -TargetRunRoot $TargetRunRoot `
            -OutputPath $comparisonPath `
            -CustomerName $CustomerName
        $reportSet.ComparisonReport = $comparison.ReportPath

        Write-Host "Generating migration readiness checklist..." -ForegroundColor Cyan
        $readiness = New-AdMigrationReadinessChecklist `
            -SourceRunRoot $currentSourceRunRoot `
            -TargetRunRoot $TargetRunRoot `
            -OutputPath $readinessPath `
            -CustomerName $CustomerName
        if ($readiness.PSObject.Properties['ReportPath']) {
            $reportSet.ReadinessChecklist = $readiness.ReportPath
        } elseif ($readiness.PSObject.Properties['ChecklistPath']) {
            $reportSet.ReadinessChecklist = $readiness.ChecklistPath
        } else {
            $reportSet.ReadinessChecklist = $readinessPath
        }
    }

    $reportSets += [pscustomobject]$reportSet
}

$results.SourceReportSets = $reportSets

if ($reportSets.Count -eq 1) {
    $results.AssessmentReport = $reportSets[0].AssessmentReport
    $results.PlanningReport = $reportSets[0].PlanningReport
    if ($reportSets[0].PSObject.Properties['ComprehensiveReport']) {
        $results.ComprehensiveReport = $reportSets[0].ComprehensiveReport
    }
    if ($reportSets[0].PSObject.Properties['ComparisonReport']) {
        $results.ComparisonReport = $reportSets[0].ComparisonReport
    }
    if ($reportSets[0].PSObject.Properties['ReadinessChecklist']) {
        $results.ReadinessChecklist = $reportSets[0].ReadinessChecklist
    }
}

if (-not $SkipWorkspace -and $WorkspaceRoot) {
    Write-Host "Generating analysis workspace..." -ForegroundColor Cyan

    $workspaceParams = @{
        SourceRunRoot = @($SourceRunRoot)
        WorkspaceRoot = $WorkspaceRoot
    }

    if ($TargetRunRoot) {
        $workspaceParams.TargetRunRoot = $TargetRunRoot
    }

    $workspace = Invoke-AdDiscoveryAnalysis @workspaceParams
    $results.AnalysisWorkspace = $workspace.WorkspaceRoot
    $results.IdentityCollisionsCsv = $workspace.IdentityCollisionsCsv
    $results.PasswordPolicyDiffCsv = $workspace.PasswordPolicyDiffCsv
}

Write-Host ""
Write-Host "Analysis complete." -ForegroundColor Green
$results.GetEnumerator() | ForEach-Object {
    $displayValue = $_.Value
    if ($displayValue -is [System.Array]) {
        if ($displayValue.Count -gt 0 -and $displayValue[0] -is [string]) {
            $displayValue = ($displayValue -join '; ')
        } else {
            $displayValue = "$($displayValue.Count) item(s)"
        }
    }

    if ($null -ne $displayValue -and -not [string]::IsNullOrWhiteSpace([string]$displayValue)) {
        Write-Host ("  {0}: {1}" -f $_.Key, $displayValue) -ForegroundColor Yellow
    }
}

[pscustomobject]$results
