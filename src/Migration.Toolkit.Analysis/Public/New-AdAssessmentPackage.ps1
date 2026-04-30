function New-AdAssessmentPackage {
    <#
    .SYNOPSIS
    Builds an HTML-first assessment package plus structured data from one or more discovery runs.

    .DESCRIPTION
    Produces a packaged assessment deliverable with:
    - HTML reports for each source run
    - Optional source-vs-target comparison and readiness reports
    - Optional shared analysis workspace
    - Curated structured dataset for downstream SQL / Power BI use
    - Package manifest and landing page

    .PARAMETER SourceRunRoot
    One or more source discovery run roots produced by Consulting.Toolkit.Discovery.

    .PARAMETER TargetRunRoot
    Optional target discovery run root. When supplied, comparison and readiness
    reports are generated for each source run and the target is included in the
    structured dataset.

    .PARAMETER OutputRoot
    Folder where the package should be written.

    .PARAMETER WorkspaceRoot
    Optional explicit analysis workspace root. If omitted and workspace
    generation is enabled, the package uses `<OutputRoot>\workspace`.

    .PARAMETER CustomerName
    Friendly customer name used in report headings and package metadata.

    .PARAMETER ExecutiveSummaryConfigPath
    Optional path to a JSON file with consultant-supplied executive summary
    overrides such as migration approach, DNS overlap assessment, and hybrid
    identity considerations.

    .PARAMETER IncludeComprehensiveReport
    Also generate the detailed comprehensive assessment report for each source.

    .PARAMETER SkipStructuredData
    Skip curated structured dataset generation in the consultant package.

    .PARAMETER CreateCustomerPackage
    Also create a customer-friendly package with polished HTML deliverables only.

    .PARAMETER ZipCustomerPackage
    When a customer package is created, also create a zip archive of the customer
    handoff folder for delivery.

    .PARAMETER SkipWorkspace
    Skip shared workspace generation.
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

        [switch]$IncludeComprehensiveReport,

        [switch]$SkipStructuredData,

        [switch]$CreateCustomerPackage,

        [switch]$ZipCustomerPackage,

        [switch]$SkipWorkspace
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Get-PackageLabel {
        param(
            [Parameter(Mandatory)]
            [string]$RunRoot,

            [Parameter(Mandatory)]
            [int]$Index
        )

        $leaf = Split-Path -Path $RunRoot -Leaf
        if ([string]::IsNullOrWhiteSpace($leaf)) {
            $leaf = "Run$Index"
        }

        $safeLeaf = ($leaf -replace '[^\w\.-]', '_').Trim('_')
        if ([string]::IsNullOrWhiteSpace($safeLeaf)) {
            $safeLeaf = "Run$Index"
        }

        return ('source_{0:00}_{1}' -f $Index, $safeLeaf)
    }

    function Get-RelativePath {
        param(
            [Parameter(Mandatory)][string]$BasePath,
            [Parameter(Mandatory)][string]$ChildPath
        )

        $baseUri = [System.Uri]((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\')
        $childUri = [System.Uri](Resolve-Path -LiteralPath $ChildPath).Path
        return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
    }

    function ConvertTo-HtmlText {
        param([AllowNull()][object]$Value)

        $text = if ($null -eq $Value) { '' } else { [string]$Value }
        return [System.Net.WebUtility]::HtmlEncode($text)
    }

    function Get-ReportDisplayName {
        param([Parameter(Mandatory)][string]$PropertyName)

        switch ($PropertyName) {
            'AssessmentReport' { return 'Executive Assessment' }
            'MigrationPlanningReport' { return 'Migration Preparation' }
            'ComprehensiveAssessmentReport' { return 'Technical Assessment' }
            'EnvironmentComparisonReport' { return 'Environment Comparison' }
            'MigrationReadinessChecklist' { return 'Migration Readiness Checklist' }
            default { return $PropertyName }
        }
    }

    $SourceRunRoot = @($SourceRunRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($SourceRunRoot.Count -eq 0) {
        throw "Provide at least one SourceRunRoot."
    }

    foreach ($path in $SourceRunRoot) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Source run root not found: $path"
        }
    }

    if ($PSBoundParameters.ContainsKey('TargetRunRoot') -and -not [string]::IsNullOrWhiteSpace($TargetRunRoot)) {
        if (-not (Test-Path -LiteralPath $TargetRunRoot -PathType Container)) {
            throw "Target run root not found: $TargetRunRoot"
        }
    }
    else {
        $TargetRunRoot = $null
    }

    $timestamp = Get-AdTimestamp -Format File

    if (-not $OutputRoot) {
        if ($SourceRunRoot.Count -eq 1) {
            $OutputRoot = Join-Path $SourceRunRoot[0] "50_assessment_package"
        }
        else {
            $OutputRoot = Join-Path (Get-Location).Path "AssessmentPackage_$timestamp"
        }
    }

    $htmlRoot = Join-Path $OutputRoot 'html'
    $dataRoot = Join-Path $OutputRoot 'data'
    $datasetRoot = Join-Path $dataRoot 'structured'

    foreach ($dir in @($OutputRoot, $htmlRoot, $dataRoot, $datasetRoot)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    if (-not $SkipWorkspace -and -not $WorkspaceRoot) {
        $WorkspaceRoot = Join-Path $OutputRoot 'workspace'
    }

    $package = [ordered]@{
        GeneratedAtUtc             = Get-AdTimestamp -Format Iso
        CustomerName               = $CustomerName
        SourceRunRoot              = @($SourceRunRoot)
        SourceRunCount             = $SourceRunRoot.Count
        TargetRunRoot              = $TargetRunRoot
        OutputRoot                 = $OutputRoot
        HtmlRoot                   = $htmlRoot
        StructuredDataRoot         = $datasetRoot
        WorkspaceRoot              = if ($SkipWorkspace) { $null } else { $WorkspaceRoot }
        IncludeComprehensiveReport = [bool]$IncludeComprehensiveReport
        CreateCustomerPackage      = [bool]$CreateCustomerPackage
        ZipCustomerPackage         = [bool]$ZipCustomerPackage
        StructuredDataIncluded     = -not $SkipStructuredData
        ExecutiveSummaryConfigPath = $ExecutiveSummaryConfigPath
        SourceReportSets           = @()
    }

    Write-Host "Building AD assessment package..." -ForegroundColor Cyan
    Write-Host "  Output: $OutputRoot" -ForegroundColor Gray
    foreach ($sourcePath in $SourceRunRoot) {
        Write-Host "  Source: $sourcePath" -ForegroundColor Gray
    }
    if ($TargetRunRoot) {
        Write-Host "  Target: $TargetRunRoot" -ForegroundColor Gray
    }

    $sourceReportSets = New-Object System.Collections.Generic.List[object]
    $allRunRoots = New-Object System.Collections.Generic.List[string]
    foreach ($sourcePath in $SourceRunRoot) {
        if (-not $allRunRoots.Contains($sourcePath)) { $allRunRoots.Add($sourcePath) }
    }
    if ($TargetRunRoot -and -not $allRunRoots.Contains($TargetRunRoot)) {
        $allRunRoots.Add($TargetRunRoot)
    }

    for ($i = 0; $i -lt $SourceRunRoot.Count; $i++) {
        $currentSourceRunRoot = $SourceRunRoot[$i]
        $sourceLabel = Get-PackageLabel -RunRoot $currentSourceRunRoot -Index ($i + 1)
        $sourceHtmlRoot = Join-Path $htmlRoot $sourceLabel
        if (-not (Test-Path -LiteralPath $sourceHtmlRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $sourceHtmlRoot -Force | Out-Null
        }

        $runData = Get-AdDiscoveryRunSummary -RunRoot $currentSourceRunRoot
        $runSummary = $runData.Summary
        $assessmentPath = Join-Path $sourceHtmlRoot "AD__Assessment__Report__$timestamp.html"
        $planningPath = Join-Path $sourceHtmlRoot "AD__Migration__Preparation__Report__$timestamp.html"

        Write-Host "Generating package reports for source $($i + 1) of $($SourceRunRoot.Count)..." -ForegroundColor Cyan
        Write-Host "  Html Output: $sourceHtmlRoot" -ForegroundColor Gray

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
        $planning = New-AdMigrationPlanningReport -DiscoveryOutputPath $currentSourceRunRoot -OutputPath $planningPath

        $reportSet = [ordered]@{
            Label                   = $sourceLabel
            SourceRunRoot           = $currentSourceRunRoot
            ForestName              = $runSummary.ForestName
            ForestRootDomain        = $runSummary.ForestRootDomain
            DomainsCount            = $runSummary.DomainsCount
            UsersTotal              = $runSummary.UsersTotal
            GroupsTotal             = $runSummary.GroupsTotal
            ComputersTotal          = $runSummary.ComputersTotal
            AssessmentReport        = $assessment.ReportPath
            AssessmentEvidenceRoot  = $assessment.EvidenceRoot
            MigrationPlanningReport = $planning.ReportPath
        }

        if ($IncludeComprehensiveReport) {
            $comprehensivePath = Join-Path $sourceHtmlRoot "AD__Comprehensive__Assessment__Report__$timestamp.html"
            $comprehensive = New-AdComprehensiveAssessmentReport -DiscoveryOutputPath $currentSourceRunRoot -OutputPath $comprehensivePath -CustomerName $CustomerName
            $reportSet.ComprehensiveAssessmentReport = $comprehensive.Path
        }

        if ($TargetRunRoot) {
            $comparisonPath = Join-Path $sourceHtmlRoot "AD__Environment__Comparison__Report__$timestamp.html"
            $readinessPath = Join-Path $sourceHtmlRoot "AD__Migration__Readiness__Checklist__$timestamp.html"

            $comparison = New-AdEnvironmentComparisonReport `
                -SourceRunRoot $currentSourceRunRoot `
                -TargetRunRoot $TargetRunRoot `
                -OutputPath $comparisonPath `
                -CustomerName $CustomerName

            $readiness = New-AdMigrationReadinessChecklist `
                -SourceRunRoot $currentSourceRunRoot `
                -TargetRunRoot $TargetRunRoot `
                -OutputPath $readinessPath `
                -CustomerName $CustomerName

            $reportSet.EnvironmentComparisonReport = $comparison.ReportPath
            if ($comparison.PSObject.Properties['DuplicateCsvPath']) {
                $reportSet.EnvironmentComparisonDuplicateCsv = $comparison.DuplicateCsvPath
            }
            if ($readiness.PSObject.Properties['ChecklistPath']) {
                $reportSet.MigrationReadinessChecklist = $readiness.ChecklistPath
            }
            else {
                $reportSet.MigrationReadinessChecklist = $readinessPath
            }
        }

        $sourceReportSets.Add([pscustomobject]$reportSet)
    }

    $package.SourceReportSets = $sourceReportSets.ToArray()

    if ($TargetRunRoot) {
        $targetRunData = Get-AdDiscoveryRunSummary -RunRoot $TargetRunRoot
        $package.TargetSummary = [pscustomobject]@{
            TargetRunRoot       = $TargetRunRoot
            ForestName          = $targetRunData.Summary.ForestName
            ForestRootDomain    = $targetRunData.Summary.ForestRootDomain
            DomainsCount        = $targetRunData.Summary.DomainsCount
            UsersTotal          = $targetRunData.Summary.UsersTotal
            GroupsTotal         = $targetRunData.Summary.GroupsTotal
            ComputersTotal      = $targetRunData.Summary.ComputersTotal
            UsersStaleCount     = $targetRunData.Summary.UsersStaleCount
            ComputersStaleCount = $targetRunData.Summary.ComputersStaleCount
        }
    }

    $workspaceResult = $null
    if (-not $SkipWorkspace -and $WorkspaceRoot) {
        Write-Host "Generating shared analysis workspace..." -ForegroundColor Cyan
        $workspaceParams = @{
            SourceRunRoot = @($SourceRunRoot)
            WorkspaceRoot = $WorkspaceRoot
        }
        if ($TargetRunRoot) {
            $workspaceParams.TargetRunRoot = $TargetRunRoot
        }

        $workspaceResult = Invoke-AdDiscoveryAnalysis @workspaceParams
        $package.AnalysisWorkspace = [pscustomobject]@{
            WorkspaceRoot         = $workspaceResult.WorkspaceRoot
            IdentityCollisionsCsv = $workspaceResult.IdentityCollisionsCsv
            PasswordPolicyDiffCsv = $workspaceResult.PasswordPolicyDiffCsv
        }
    }

    $dataset = $null
    if (-not $SkipStructuredData) {
        Write-Host "Exporting structured dataset..." -ForegroundColor Cyan
        $datasetParams = @{
            RunRoot    = $allRunRoots.ToArray()
            OutputRoot = $datasetRoot
        }
        if ($workspaceResult) {
            $datasetParams.WorkspaceRoot = $workspaceResult.WorkspaceRoot
        }
        $dataset = Export-AdPowerBiDataset @datasetParams

        $package.StructuredData = [pscustomobject]@{
            OutputRoot    = $dataset.OutputRoot
            ManifestPath  = $dataset.ManifestPath
            TablesWritten = $dataset.TablesWritten
            Tables        = $dataset.Tables
        }
    }

    $manifestPath = Join-Path $OutputRoot 'AssessmentPackage.json'
    $package | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $indexPath = Join-Path $OutputRoot 'index.html'
    $landingHtml = New-Object System.Text.StringBuilder
    [void]$landingHtml.AppendLine('<!DOCTYPE html>')
    [void]$landingHtml.AppendLine('<html lang="en">')
    [void]$landingHtml.AppendLine('<head>')
    [void]$landingHtml.AppendLine('  <meta charset="UTF-8">')
    [void]$landingHtml.AppendLine('  <meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$landingHtml.AppendLine("  <title>Assessment Package - $(ConvertTo-HtmlText $CustomerName)</title>")
    [void]$landingHtml.AppendLine('  <style>')
    [void]$landingHtml.AppendLine("    body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; background: #f3f5f7; color: #1f2933; margin: 0; }")
    [void]$landingHtml.AppendLine('    .container { max-width: 1280px; margin: 0 auto; padding: 24px; }')
    [void]$landingHtml.AppendLine('    .hero { background: linear-gradient(135deg, #0f3d56, #1f6f8b); color: white; padding: 32px; border-radius: 12px; box-shadow: 0 10px 30px rgba(15,61,86,0.18); }')
    [void]$landingHtml.AppendLine('    .hero h1 { margin: 0 0 8px 0; font-size: 30px; }')
    [void]$landingHtml.AppendLine('    .hero p { margin: 4px 0; opacity: 0.92; }')
    [void]$landingHtml.AppendLine('    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-top: 20px; }')
    [void]$landingHtml.AppendLine('    .card { background: white; border-radius: 12px; padding: 20px; box-shadow: 0 3px 12px rgba(0,0,0,0.08); }')
    [void]$landingHtml.AppendLine('    .card h2, .card h3 { margin-top: 0; color: #0f3d56; }')
    [void]$landingHtml.AppendLine('    .kpi { font-size: 30px; font-weight: 700; color: #0f3d56; margin: 6px 0; }')
    [void]$landingHtml.AppendLine('    .section { margin-top: 24px; }')
    [void]$landingHtml.AppendLine('    .section h2 { color: #0f3d56; margin-bottom: 14px; }')
    [void]$landingHtml.AppendLine('    .source-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 18px; }')
    [void]$landingHtml.AppendLine('    ul { margin: 10px 0 0 18px; padding: 0; }')
    [void]$landingHtml.AppendLine('    li { margin: 6px 0; }')
    [void]$landingHtml.AppendLine('    a { color: #125d98; text-decoration: none; }')
    [void]$landingHtml.AppendLine('    a:hover { text-decoration: underline; }')
    [void]$landingHtml.AppendLine('    .meta { font-size: 13px; color: #52606d; }')
    [void]$landingHtml.AppendLine('    .pill { display: inline-block; margin-right: 8px; margin-top: 8px; background: #d9eef7; color: #0f3d56; padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; }')
    [void]$landingHtml.AppendLine('    table { width: 100%; border-collapse: collapse; margin-top: 10px; }')
    [void]$landingHtml.AppendLine('    th, td { padding: 10px 8px; border-bottom: 1px solid #e6eaee; text-align: left; font-size: 14px; }')
    [void]$landingHtml.AppendLine('    th { color: #52606d; font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; }')
    [void]$landingHtml.AppendLine('  </style>')
    [void]$landingHtml.AppendLine('</head>')
    [void]$landingHtml.AppendLine('<body>')
    [void]$landingHtml.AppendLine('  <div class="container">')
    [void]$landingHtml.AppendLine('    <div class="hero">')
    [void]$landingHtml.AppendLine('      <h1>Active Directory Assessment Package</h1>')
    [void]$landingHtml.AppendLine("      <p>Customer: $(ConvertTo-HtmlText $CustomerName)</p>")
    [void]$landingHtml.AppendLine("      <p>Generated: $(ConvertTo-HtmlText ([string]$package.GeneratedAtUtc))</p>")
    [void]$landingHtml.AppendLine('      <p>Primary deliverable: HTML assessment reports with optional supporting data for consulting workflows.</p>')
    [void]$landingHtml.AppendLine('    </div>')
    [void]$landingHtml.AppendLine('    <div class="grid">')
    [void]$landingHtml.AppendLine("      <div class=""card""><div class=""meta"">Source Runs</div><div class=""kpi"">$($SourceRunRoot.Count)</div></div>")
    [void]$landingHtml.AppendLine("      <div class=""card""><div class=""meta"">Target Included</div><div class=""kpi"">$(if ($TargetRunRoot) { 'Yes' } else { 'No' })</div></div>")
    [void]$landingHtml.AppendLine("      <div class=""card""><div class=""meta"">Structured Tables</div><div class=""kpi"">$(if ($dataset) { $dataset.TablesWritten } else { 'Skipped' })</div></div>")
    [void]$landingHtml.AppendLine("      <div class=""card""><div class=""meta"">Workspace</div><div class=""kpi"">$(if ($workspaceResult) { 'Included' } else { 'Skipped' })</div></div>")
    [void]$landingHtml.AppendLine('    </div>')
    if ($CreateCustomerPackage) {
        [void]$landingHtml.AppendLine('    <div class="section">')
        [void]$landingHtml.AppendLine('      <div class="card">')
        [void]$landingHtml.AppendLine('        <h2>Customer Package</h2>')
        [void]$landingHtml.AppendLine('        <p class="meta">A separate customer-facing package is included with only polished HTML deliverables and no structured data or workspace artifacts.</p>')
        [void]$landingHtml.AppendLine('      </div>')
        [void]$landingHtml.AppendLine('    </div>')
    }
    [void]$landingHtml.AppendLine('    <div class="section">')
    [void]$landingHtml.AppendLine('      <h2>Source Assessments</h2>')
    [void]$landingHtml.AppendLine('      <div class="source-grid">')
    foreach ($reportSet in $sourceReportSets) {
        [void]$landingHtml.AppendLine('        <div class="card">')
        [void]$landingHtml.AppendLine("          <h3>$(ConvertTo-HtmlText $reportSet.ForestName)</h3>")
        [void]$landingHtml.AppendLine("          <div class=""meta"">$(ConvertTo-HtmlText $reportSet.SourceRunRoot)</div>")
        [void]$landingHtml.AppendLine("          <span class=""pill"">Domains: $(ConvertTo-HtmlText $reportSet.DomainsCount)</span>")
        [void]$landingHtml.AppendLine("          <span class=""pill"">Users: $(ConvertTo-HtmlText $reportSet.UsersTotal)</span>")
        [void]$landingHtml.AppendLine("          <span class=""pill"">Computers: $(ConvertTo-HtmlText $reportSet.ComputersTotal)</span>")
        [void]$landingHtml.AppendLine('          <ul>')
        foreach ($linkProp in @('AssessmentReport', 'MigrationPlanningReport', 'ComprehensiveAssessmentReport', 'EnvironmentComparisonReport', 'MigrationReadinessChecklist')) {
            if ($reportSet.PSObject.Properties[$linkProp] -and $reportSet.$linkProp) {
                $relativeLink = Get-RelativePath -BasePath $OutputRoot -ChildPath $reportSet.$linkProp
                [void]$landingHtml.AppendLine("            <li><a href=""$(ConvertTo-HtmlText ($relativeLink -replace '\\','/'))"">$(ConvertTo-HtmlText (Get-ReportDisplayName -PropertyName $linkProp))</a></li>")
            }
        }
        [void]$landingHtml.AppendLine('          </ul>')
        [void]$landingHtml.AppendLine('        </div>')
    }
    [void]$landingHtml.AppendLine('      </div>')
    [void]$landingHtml.AppendLine('    </div>')

    if ($TargetRunRoot -and $package.TargetSummary) {
        [void]$landingHtml.AppendLine('    <div class="section">')
        [void]$landingHtml.AppendLine('      <h2>Target Environment</h2>')
        [void]$landingHtml.AppendLine('      <div class="card">')
        [void]$landingHtml.AppendLine("        <h3>$(ConvertTo-HtmlText $package.TargetSummary.ForestName)</h3>")
        [void]$landingHtml.AppendLine("        <div class=""meta"">$(ConvertTo-HtmlText $package.TargetSummary.TargetRunRoot)</div>")
        [void]$landingHtml.AppendLine('        <table>')
        [void]$landingHtml.AppendLine('          <tr><th>Domains</th><th>Users</th><th>Groups</th><th>Computers</th></tr>')
        [void]$landingHtml.AppendLine("          <tr><td>$(ConvertTo-HtmlText $package.TargetSummary.DomainsCount)</td><td>$(ConvertTo-HtmlText $package.TargetSummary.UsersTotal)</td><td>$(ConvertTo-HtmlText $package.TargetSummary.GroupsTotal)</td><td>$(ConvertTo-HtmlText $package.TargetSummary.ComputersTotal)</td></tr>")
        [void]$landingHtml.AppendLine('        </table>')
        [void]$landingHtml.AppendLine('      </div>')
        [void]$landingHtml.AppendLine('    </div>')
    }

    if ($dataset) {
        [void]$landingHtml.AppendLine('    <div class="section">')
        [void]$landingHtml.AppendLine('      <h2>Structured Data</h2>')
        [void]$landingHtml.AppendLine('      <div class="card">')
        $datasetManifestRelative = Get-RelativePath -BasePath $OutputRoot -ChildPath $dataset.ManifestPath
        [void]$landingHtml.AppendLine("        <p class=""meta"">Curated dataset manifest: <a href=""$(ConvertTo-HtmlText ($datasetManifestRelative -replace '\\','/'))"">DatasetManifest.json</a></p>")
        [void]$landingHtml.AppendLine('        <table>')
        [void]$landingHtml.AppendLine('          <tr><th>Table</th><th>Rows</th><th>Type</th></tr>')
        foreach ($table in @($dataset.Tables)) {
            [void]$landingHtml.AppendLine("          <tr><td>$(ConvertTo-HtmlText $table.Name)</td><td>$(ConvertTo-HtmlText $table.Rows)</td><td>$(ConvertTo-HtmlText $table.Type)</td></tr>")
        }
        [void]$landingHtml.AppendLine('        </table>')
        [void]$landingHtml.AppendLine('      </div>')
        [void]$landingHtml.AppendLine('    </div>')
    }

    if ($workspaceResult) {
        [void]$landingHtml.AppendLine('    <div class="section">')
        [void]$landingHtml.AppendLine('      <h2>Cross-Run Analysis</h2>')
        [void]$landingHtml.AppendLine('      <div class="card">')
        [void]$landingHtml.AppendLine("        <p class=""meta"">Workspace root: $(ConvertTo-HtmlText $workspaceResult.WorkspaceRoot)</p>")
        [void]$landingHtml.AppendLine('        <ul>')
        foreach ($workspaceProp in @('IdentityCollisionsCsv', 'PasswordPolicyDiffCsv')) {
            if ($workspaceResult.PSObject.Properties[$workspaceProp] -and $workspaceResult.$workspaceProp) {
                $workspaceRelative = Get-RelativePath -BasePath $OutputRoot -ChildPath $workspaceResult.$workspaceProp
                [void]$landingHtml.AppendLine("          <li><a href=""$(ConvertTo-HtmlText ($workspaceRelative -replace '\\','/'))"">$(ConvertTo-HtmlText $workspaceProp)</a></li>")
            }
        }
        [void]$landingHtml.AppendLine('        </ul>')
        [void]$landingHtml.AppendLine('      </div>')
        [void]$landingHtml.AppendLine('    </div>')
    }

    [void]$landingHtml.AppendLine('  </div>')
    [void]$landingHtml.AppendLine('</body>')
    [void]$landingHtml.AppendLine('</html>')
    $landingHtml.ToString() | Set-Content -LiteralPath $indexPath -Encoding UTF8

    $customerPackageRoot = $null
    $customerZipPath = $null
    if ($CreateCustomerPackage) {
        Write-Host "Creating customer package..." -ForegroundColor Cyan
        $customerPackageRoot = Join-Path $OutputRoot 'customer'
        $customerReportsRoot = Join-Path $customerPackageRoot 'Reports'

        foreach ($dir in @($customerPackageRoot, $customerReportsRoot)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        foreach ($reportSet in $sourceReportSets) {
            $customerSourceRoot = Join-Path $customerReportsRoot $reportSet.Label
            if (-not (Test-Path -LiteralPath $customerSourceRoot -PathType Container)) {
                New-Item -ItemType Directory -Path $customerSourceRoot -Force | Out-Null
            }

            foreach ($linkProp in @('AssessmentReport', 'MigrationPlanningReport', 'EnvironmentComparisonReport', 'MigrationReadinessChecklist')) {
                if ($reportSet.PSObject.Properties[$linkProp] -and $reportSet.$linkProp) {
                    Copy-Item -LiteralPath $reportSet.$linkProp -Destination (Join-Path $customerSourceRoot (Split-Path -Leaf $reportSet.$linkProp)) -Force
                }
            }

            if ($reportSet.PSObject.Properties['AssessmentEvidenceRoot'] -and
                $reportSet.AssessmentEvidenceRoot -and
                (Test-Path -LiteralPath $reportSet.AssessmentEvidenceRoot -PathType Container)) {
                $evidenceDestination = Join-Path $customerSourceRoot (Split-Path -Leaf $reportSet.AssessmentEvidenceRoot)
                Copy-Item -LiteralPath $reportSet.AssessmentEvidenceRoot -Destination $evidenceDestination -Recurse -Force
            }

            if ($reportSet.PSObject.Properties['EnvironmentComparisonDuplicateCsv'] -and
                $reportSet.EnvironmentComparisonDuplicateCsv -and
                (Test-Path -LiteralPath $reportSet.EnvironmentComparisonDuplicateCsv -PathType Leaf)) {
                Copy-Item -LiteralPath $reportSet.EnvironmentComparisonDuplicateCsv -Destination (Join-Path $customerSourceRoot (Split-Path -Leaf $reportSet.EnvironmentComparisonDuplicateCsv)) -Force
            }
        }

        $customerIndexPath = Join-Path $customerPackageRoot 'index.html'
        $customerReadmePath = Join-Path $customerPackageRoot 'README.txt'
        $customerHtml = New-Object System.Text.StringBuilder
        [void]$customerHtml.AppendLine('<!DOCTYPE html>')
        [void]$customerHtml.AppendLine('<html lang="en">')
        [void]$customerHtml.AppendLine('<head>')
        [void]$customerHtml.AppendLine('  <meta charset="UTF-8">')
        [void]$customerHtml.AppendLine('  <meta name="viewport" content="width=device-width, initial-scale=1.0">')
        [void]$customerHtml.AppendLine("  <title>Assessment Summary - $(ConvertTo-HtmlText $CustomerName)</title>")
        [void]$customerHtml.AppendLine('  <style>')
        [void]$customerHtml.AppendLine("    body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; background: #f7f9fb; color: #243b53; margin: 0; }")
        [void]$customerHtml.AppendLine('    .container { max-width: 1180px; margin: 0 auto; padding: 28px; }')
        [void]$customerHtml.AppendLine('    .hero { background: linear-gradient(135deg, #154360, #1f618d); color: white; padding: 36px; border-radius: 14px; box-shadow: 0 14px 34px rgba(21,67,96,0.18); }')
        [void]$customerHtml.AppendLine('    .hero h1 { margin: 0 0 10px 0; font-size: 32px; }')
        [void]$customerHtml.AppendLine('    .hero p { margin: 6px 0; opacity: 0.94; }')
        [void]$customerHtml.AppendLine('    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; margin-top: 22px; }')
        [void]$customerHtml.AppendLine('    .card { background: white; border-radius: 14px; padding: 22px; box-shadow: 0 4px 18px rgba(0,0,0,0.08); }')
        [void]$customerHtml.AppendLine('    .card h2, .card h3 { margin-top: 0; color: #154360; }')
        [void]$customerHtml.AppendLine('    .meta { color: #5d6d7e; font-size: 13px; }')
        [void]$customerHtml.AppendLine('    .kpi { font-size: 30px; font-weight: 700; color: #154360; margin: 6px 0; }')
        [void]$customerHtml.AppendLine('    .section { margin-top: 26px; }')
        [void]$customerHtml.AppendLine('    .source-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); gap: 18px; }')
        [void]$customerHtml.AppendLine('    .pill { display: inline-block; margin-right: 8px; margin-top: 8px; background: #ebf5fb; color: #154360; padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; }')
        [void]$customerHtml.AppendLine('    ul { margin: 12px 0 0 18px; padding: 0; }')
        [void]$customerHtml.AppendLine('    li { margin: 8px 0; }')
        [void]$customerHtml.AppendLine('    a { color: #1a5276; text-decoration: none; font-weight: 600; }')
        [void]$customerHtml.AppendLine('    a:hover { text-decoration: underline; }')
        [void]$customerHtml.AppendLine('    table { width: 100%; border-collapse: collapse; margin-top: 12px; }')
        [void]$customerHtml.AppendLine('    th, td { padding: 10px 8px; border-bottom: 1px solid #e5e8eb; text-align: left; }')
        [void]$customerHtml.AppendLine('    th { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: #5d6d7e; }')
        [void]$customerHtml.AppendLine('  </style>')
        [void]$customerHtml.AppendLine('</head>')
        [void]$customerHtml.AppendLine('<body>')
        [void]$customerHtml.AppendLine('  <div class="container">')
        [void]$customerHtml.AppendLine('    <div class="hero">')
        [void]$customerHtml.AppendLine('      <h1>Active Directory Assessment</h1>')
        [void]$customerHtml.AppendLine("      <p>Customer: $(ConvertTo-HtmlText $CustomerName)</p>")
        [void]$customerHtml.AppendLine('      <p>This package contains the customer-facing assessment deliverables and planning summaries.</p>')
        [void]$customerHtml.AppendLine("      <p>Generated: $(ConvertTo-HtmlText ([string]$package.GeneratedAtUtc))</p>")
        [void]$customerHtml.AppendLine('    </div>')
        [void]$customerHtml.AppendLine('    <div class="grid">')
        [void]$customerHtml.AppendLine("      <div class=""card""><div class=""meta"">Source Environments</div><div class=""kpi"">$($SourceRunRoot.Count)</div></div>")
        [void]$customerHtml.AppendLine("      <div class=""card""><div class=""meta"">Target Included</div><div class=""kpi"">$(if ($TargetRunRoot) { 'Yes' } else { 'No' })</div></div>")
        [void]$customerHtml.AppendLine("      <div class=""card""><div class=""meta"">Assessment Format</div><div class=""kpi"">HTML</div></div>")
        [void]$customerHtml.AppendLine("      <div class=""card""><div class=""meta"">Technical Data</div><div class=""kpi"">Hidden</div></div>")
        [void]$customerHtml.AppendLine('    </div>')
        [void]$customerHtml.AppendLine('    <div class="section">')
        [void]$customerHtml.AppendLine('      <h2>Assessment Deliverables</h2>')
        [void]$customerHtml.AppendLine('      <div class="source-grid">')
        foreach ($reportSet in $sourceReportSets) {
            [void]$customerHtml.AppendLine('        <div class="card">')
            [void]$customerHtml.AppendLine("          <h3>$(ConvertTo-HtmlText $reportSet.ForestName)</h3>")
            [void]$customerHtml.AppendLine('          <div class="meta">Source environment assessment</div>')
            [void]$customerHtml.AppendLine("          <span class=""pill"">Domains: $(ConvertTo-HtmlText $reportSet.DomainsCount)</span>")
            [void]$customerHtml.AppendLine("          <span class=""pill"">Users: $(ConvertTo-HtmlText $reportSet.UsersTotal)</span>")
            [void]$customerHtml.AppendLine("          <span class=""pill"">Computers: $(ConvertTo-HtmlText $reportSet.ComputersTotal)</span>")
            [void]$customerHtml.AppendLine('          <ul>')
            foreach ($linkProp in @('AssessmentReport', 'MigrationPlanningReport', 'EnvironmentComparisonReport', 'MigrationReadinessChecklist')) {
                if ($reportSet.PSObject.Properties[$linkProp] -and $reportSet.$linkProp) {
                    $customerFile = Join-Path "Reports/$($reportSet.Label)" (Split-Path -Leaf $reportSet.$linkProp)
                    [void]$customerHtml.AppendLine("            <li><a href=""$(ConvertTo-HtmlText ($customerFile -replace '\\','/'))"">$(ConvertTo-HtmlText (Get-ReportDisplayName -PropertyName $linkProp))</a></li>")
                }
            }
            [void]$customerHtml.AppendLine('          </ul>')
            [void]$customerHtml.AppendLine('        </div>')
        }
        [void]$customerHtml.AppendLine('      </div>')
        [void]$customerHtml.AppendLine('    </div>')

        if ($TargetRunRoot -and $package.TargetSummary) {
            [void]$customerHtml.AppendLine('    <div class="section">')
            [void]$customerHtml.AppendLine('      <h2>Target Environment Summary</h2>')
            [void]$customerHtml.AppendLine('      <div class="card">')
            [void]$customerHtml.AppendLine("        <h3>$(ConvertTo-HtmlText $package.TargetSummary.ForestName)</h3>")
            [void]$customerHtml.AppendLine('        <table>')
            [void]$customerHtml.AppendLine('          <tr><th>Domains</th><th>Users</th><th>Groups</th><th>Computers</th></tr>')
            [void]$customerHtml.AppendLine("          <tr><td>$(ConvertTo-HtmlText $package.TargetSummary.DomainsCount)</td><td>$(ConvertTo-HtmlText $package.TargetSummary.UsersTotal)</td><td>$(ConvertTo-HtmlText $package.TargetSummary.GroupsTotal)</td><td>$(ConvertTo-HtmlText $package.TargetSummary.ComputersTotal)</td></tr>")
            [void]$customerHtml.AppendLine('        </table>')
            [void]$customerHtml.AppendLine('      </div>')
            [void]$customerHtml.AppendLine('    </div>')
        }

        [void]$customerHtml.AppendLine('  </div>')
        [void]$customerHtml.AppendLine('</body>')
        [void]$customerHtml.AppendLine('</html>')
        $customerHtml.ToString() | Set-Content -LiteralPath $customerIndexPath -Encoding UTF8
        @(
            'Active Directory Assessment Package',
            '',
            'Start here:',
            '1. Extract the full zip to a local folder if this package was delivered as a zip file.',
            '2. Open index.html in a web browser.',
            '3. Choose the report for your environment.',
            '4. Inside each Executive Assessment report, use the "View evidence" and "Download CSV" links for supporting detail.',
            '',
            'Package contents:',
            '- index.html: main landing page',
            '- Reports\: customer-facing reports and supporting evidence folders',
            '',
            'Important:',
            '- Keep this folder structure intact so report links and downloads continue to work.',
            '- Do not move individual HTML files away from their matching evidence folders.'
        ) | Set-Content -LiteralPath $customerReadmePath -Encoding UTF8
        $package.CustomerPackageRoot = $customerPackageRoot
        $package.CustomerIndexPath = $customerIndexPath
        $package.CustomerReadmePath = $customerReadmePath

        if ($ZipCustomerPackage) {
            $customerZipPath = Join-Path $OutputRoot ("{0}_customer_package.zip" -f $timestamp)
            if (Test-Path -LiteralPath $customerZipPath -PathType Leaf) {
                Remove-Item -LiteralPath $customerZipPath -Force
            }

            Compress-Archive -LiteralPath $customerPackageRoot -DestinationPath $customerZipPath -CompressionLevel Optimal -Force
            $package.CustomerZipPath = $customerZipPath
        }
    }

    return [pscustomobject]@{
        OutputRoot         = $OutputRoot
        IndexPath          = $indexPath
        ManifestPath       = $manifestPath
        HtmlRoot           = $htmlRoot
        StructuredDataRoot = if ($dataset) { $datasetRoot } else { $null }
        WorkspaceRoot      = if ($workspaceResult) { $workspaceResult.WorkspaceRoot } else { $null }
        SourceRunCount     = $SourceRunRoot.Count
        HasTarget          = [bool]$TargetRunRoot
        TablesWritten      = if ($dataset) { $dataset.TablesWritten } else { 0 }
        CustomerPackageRoot = $customerPackageRoot
        CustomerIndexPath   = if ($customerPackageRoot) { Join-Path $customerPackageRoot 'index.html' } else { $null }
        CustomerReadmePath  = if ($customerPackageRoot) { Join-Path $customerPackageRoot 'README.txt' } else { $null }
        CustomerZipPath     = $customerZipPath
        SourceReportSets   = $sourceReportSets.ToArray()
    }
}
