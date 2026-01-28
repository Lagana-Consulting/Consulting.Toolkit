function Invoke-AdDiscoveryAnalysis {
    <#
    .SYNOPSIS
    Performs offline analysis of AD discovery data and generates comprehensive reports.

    .DESCRIPTION
    Analyzes pre-collected AD discovery CSV data from source and target environments
    to generate:
    - Source and target assessment reports (HTML)
    - Migration planning report
    - Environment comparison report (HTML)
    - Cross-forest duplicate object analysis

    No live Active Directory queries are performed—all analysis is based on CSV data
    from discovery runs. Supports multi-source forest scenarios.

    Requires PowerShell 7+ (Analysis module requirement).

    .PARAMETER ConfigFile
    Path to JSON configuration file containing:
    - SourceRunRoots (array): Source discovery output paths
    - TargetRunRoot (string): Target discovery output path
    - CustomerName (string): Organization name for reports
    - OutputRoot (string): Analysis output directory

    .PARAMETER SourceRunRoot
    Array of paths to source environment discovery output folders.
    Used when not providing ConfigFile. Required in Manual parameter set.

    .PARAMETER TargetRunRoot
    Path to target environment discovery output folder.
    Used when not providing ConfigFile. Required in Manual parameter set.

    .PARAMETER CustomerName
    Customer/organization name for report headers and titles.
    Default is "Organization".

    .PARAMETER OutputRoot
    Root directory for analysis outputs. If not specified, creates
    'Analysis_{timestamp}' folder in current directory.

    .PARAMETER ExcludeBuiltIn
    Exclude built-in users, groups, and computer accounts (e.g., Administrator, Domain Admins)
    from duplicate analysis.

    .PARAMETER GenerateLoeForBoth
    [Deprecated] LOE workbook generation has been removed.

    .PARAMETER IncludeTargetPlanning
    Generate migration planning report for target environment.
    Useful for understanding target environment preparation needs.

    .PARAMETER OpenReports
    Automatically open generated HTML reports in browser after creation.

    .EXAMPLE
    Invoke-AdDiscoveryAnalysis -ConfigFile "C:\Analysis\config.json"

    Runs analysis using configuration file.

    .EXAMPLE
    Invoke-AdDiscoveryAnalysis `
      -SourceRunRoot "C:\Discovery\Source_20260128-100000" `
      -TargetRunRoot "C:\Discovery\Target_20260128-110000" `
      -CustomerName "Contoso Corp" `
      -OutputRoot "C:\Analysis" `
      -OpenReports

    Runs analysis with manual parameters and opens reports.

    .EXAMPLE
    # Multi-source forest scenario
    Invoke-AdDiscoveryAnalysis `
      -SourceRunRoot @("C:\Discovery\Forest1", "C:\Discovery\Forest2") `
      -TargetRunRoot "C:\Discovery\Target" `
      -CustomerName "Multi-Forest Migration" `
      -IncludeTargetPlanning

    Analyzes multiple source forests against single target.

    .OUTPUTS
    Generated reports in OutputRoot:
    - Source_Assessment_{timestamp}.html
    - Target_Assessment_{timestamp}.html (if IncludeTargetPlanning)
    - Migration_Planning_{timestamp}.html
    - Environment_Comparison_{timestamp}.html
    - CrossForest_Duplicates_{timestamp}.csv

    .NOTES
    Requires PowerShell 7+.
    Discovery data must be from Migration.Toolkit discovery runs (expected CSV schema).
    Config file format: { "SourceRunRoots": [...], "TargetRunRoot": "...", "CustomerName": "...", "OutputRoot": "..." }

    .LINK
    New-AdComprehensiveAssessmentReport
    New-AdMigrationPlanningReport
    Invoke-AdCrossForestDuplicateCheck
    #>
    [CmdletBinding(DefaultParameterSetName = 'Manual')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Config')]
        [string]$ConfigFile,

        [Parameter(Mandatory, ParameterSetName = 'Manual')]
        [string[]]$SourceRunRoot,

        [Parameter(Mandatory, ParameterSetName = 'Manual')]
        [string]$TargetRunRoot,

        [Parameter(ParameterSetName = 'Manual')]
        [string]$CustomerName = "Organization",

        [Parameter(ParameterSetName = 'Manual')]
        [string]$OutputRoot,

        [Parameter()]
        [switch]$ExcludeBuiltIn,

        [switch]$GenerateLoeForBoth,
        [switch]$IncludeTargetPlanning,
        [switch]$OpenReports
    )

    # ========================================
    # Load config if provided
    # ========================================
    if ($PSCmdlet.ParameterSetName -eq 'Config') {
        if (-not (Test-Path -LiteralPath $ConfigFile)) {
            throw "Config file not found: $ConfigFile"
        }
        try {
            $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json

            # Support both SourceRunRoots (array) and SourceRunRoot (string) for backward compatibility
            if ($config.PSObject.Properties['SourceRunRoots']) {
                $SourceRunRoot = $config.SourceRunRoots
            } elseif ($config.PSObject.Properties['SourceRunRoot']) {
                $SourceRunRoot = @($config.SourceRunRoot)
            } else {
                throw "Config must contain SourceRunRoot or SourceRunRoots"
            }
            $TargetRunRoot = $config.TargetRunRoot
            $CustomerName = if ($config.CustomerName) { $config.CustomerName } else { "Organization" }
            $OutputRoot = if ($config.OutputRoot) { $config.OutputRoot } else { $SourceRunRoot[0] }
            if ($config.PSObject.Properties['GenerateLoeForBoth']) { $GenerateLoeForBoth = [bool]$config.GenerateLoeForBoth }
            if ($config.PSObject.Properties['IncludeTargetPlanning']) { $IncludeTargetPlanning = [bool]$config.IncludeTargetPlanning }
        } catch {
            throw "Failed to parse config file: $_"
        }
    }

    # Normalize SourceRunRoot to array if single string
    if ($SourceRunRoot -isnot [array]) {
        $SourceRunRoot = @($SourceRunRoot)
    }

    # Validate paths
    foreach ($srcRoot in $SourceRunRoot) {
        if (-not (Test-Path -LiteralPath $srcRoot)) {
            throw "Source run root not found: $srcRoot"
        }
    }
    if (-not (Test-Path -LiteralPath $TargetRunRoot)) {
        throw "Target run root not found: $TargetRunRoot"
    }

    # Create output root if missing
    if (-not (Test-Path -LiteralPath $OutputRoot)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }

    # Define all output paths upfront
    $sourceAssessmentPath = Join-Path $OutputRoot "AD__Assessment__Report__Source.html"
    $targetAssessmentPath = Join-Path $OutputRoot "AD__Assessment__Report__Target.html"
    $targetComprehensivePath = Join-Path $OutputRoot "AD__Comprehensive__Assessment__Target.html"
    $comparisonPath = Join-Path $OutputRoot "AD__Environment__Comparison__Report.html"
    $duplicatePath = Join-Path $OutputRoot "AD__Duplicate__Objects__Cross_Forest.csv"
    $planningPath = Join-Path $OutputRoot "AD__Migration__Planning__Report__Source.html"

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "AD Discovery Analysis Engine" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Sources: $($SourceRunRoot.Count) forest(s)" -ForegroundColor White
    foreach ($src in $SourceRunRoot) {
        Write-Host "  - $src" -ForegroundColor White
    }
    Write-Host "Target: $TargetRunRoot" -ForegroundColor White
    Write-Host "Output: $OutputRoot" -ForegroundColor White
    Write-Host ""

    # Helper to safely import CSV
    function Import-CsvSafe([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) {
            return @()
        }
        try {
            return @(Import-Csv -Path $Path -ErrorAction Stop)
        } catch {
            Write-Warning "Failed to import $Path : $_"
            return @()
        }
    }

    # Helper to find CSV files by pattern (handles wildcards)
    function Find-CsvFile([string]$SearchPath) {
        if (-not (Test-Path -Path $SearchPath)) {
            return @()
        }

        return @(Get-ChildItem -Path $SearchPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    }

    # ========================================
    # Step 1: Generate per-source assessment reports
    # ========================================
    Write-Host "[1/6] Generating source environment assessments..." -ForegroundColor Yellow
    $assessmentSources = @()
    $sourceAssessmentPaths = @()
    $sourceComprehensivePaths = @()

    foreach ($srcRoot in $SourceRunRoot) {
        # Extract forest/domain prefix from path
        $pathParts = Split-Path -Path $srcRoot -Leaf
        $prefix = if ($pathParts -match '^([A-Za-z0-9_]+)') { $matches[1] } else { "Source" }

        # Generate per-source assessment with suffix
        $srcAssessmentPath = Join-Path $OutputRoot "AD__Assessment__Report__Source__$prefix.html"
        $srcComprehensivePath = Join-Path $OutputRoot "AD__Comprehensive__Assessment__Source__$prefix.html"

        try {
            $assessment = New-AdAssessmentReport -DiscoveryOutputPath $srcRoot -OutputPath $srcAssessmentPath
            Write-Host "  [OK] Source assessment ($prefix): $srcAssessmentPath" -ForegroundColor Green
            $assessmentSources += @{ Prefix = $prefix; Path = $srcAssessmentPath; Data = $assessment }
            $sourceAssessmentPaths += $srcAssessmentPath
        } catch {
            Write-Warning "Source assessment ($prefix) failed: $_"
        }

        # Generate comprehensive assessment report
        try {
            $comprehensiveAssessment = New-AdComprehensiveAssessmentReport -DiscoveryOutputPath $srcRoot -OutputPath $srcComprehensivePath -CustomerName $CustomerName
            Write-Host "  [OK] Comprehensive assessment ($prefix): $srcComprehensivePath" -ForegroundColor Green
            $sourceComprehensivePaths += $srcComprehensivePath
        } catch {
            Write-Warning "Comprehensive assessment ($prefix) failed: $_"
        }
    }
    Write-Host ""

    # ========================================
    # Step 2: Generate target assessment report
    # ========================================
    Write-Host "[2/6] Generating target environment assessment..." -ForegroundColor Yellow
    try {
        $assessmentTarget = New-AdAssessmentReport -DiscoveryOutputPath $TargetRunRoot -OutputPath $targetAssessmentPath
        Write-Host "  [OK] Target assessment: $targetAssessmentPath" -ForegroundColor Green
    } catch {
        Write-Warning "Target assessment failed: $_"
        $assessmentTarget = $null
    }

    # Generate comprehensive assessment for target
    try {
        $comprehensiveTarget = New-AdComprehensiveAssessmentReport -DiscoveryOutputPath $TargetRunRoot -OutputPath $targetComprehensivePath -CustomerName $CustomerName
        Write-Host "  [OK] Comprehensive assessment (target): $targetComprehensivePath" -ForegroundColor Green
    } catch {
        Write-Warning "Comprehensive target assessment failed: $_"
        $comprehensiveTarget = $null
    }
    Write-Host ""

    # ========================================
    # Step 3: Generate environment comparison
    # ========================================
    Write-Host "[3/6] Generating environment comparison report..." -ForegroundColor Yellow
    try {
        $comparisonReport = New-AdEnvironmentComparisonReport -SourceRunRoot $SourceRunRoot[0] -TargetRunRoot $TargetRunRoot -OutputPath $comparisonPath -CustomerName $CustomerName
        Write-Host "  [OK] Comparison report: $comparisonPath" -ForegroundColor Green
    } catch {
        Write-Warning "Comparison report failed: $_"
        $comparisonReport = $null
    }
    Write-Host ""

    # ========================================
    # Step 4: Generate readiness checklist
    # ========================================
    # ========================================
    # Step 4: Cross-forest duplicate object analysis
    # ========================================
    Write-Host "[4/5] Analyzing cross-forest duplicate objects..." -ForegroundColor Yellow
    $crossForestDuplicates = @()
    try {
        $sourceUsers = @()
        $sourceGroups = @()
        $sourceComputers = @()
        $targetUsers = @()
        $targetGroups = @()
        $targetComputers = @()

        # Load source objects from all source roots
        foreach ($srcRoot in $SourceRunRoot) {
            $sourceDomainDir = Join-Path $srcRoot '20_domains'
            if (Test-Path -LiteralPath $sourceDomainDir) {
                Get-ChildItem -Path $sourceDomainDir -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
                    $domainFolder = $_.FullName

                    $userPattern = Join-Path $domainFolder 'AD__Domain__Identity__Users__*.csv'
                    @(Find-CsvFile $userPattern) | ForEach-Object { $sourceUsers += Import-CsvSafe $_ }

                    $groupPattern = Join-Path $domainFolder 'AD__Domain__Identity__Groups__*.csv'
                    @(Find-CsvFile $groupPattern) | ForEach-Object { $sourceGroups += Import-CsvSafe $_ }

                    $compPattern = Join-Path $domainFolder 'AD__Domain__Identity__ComputersAll__*.csv'
                    @(Find-CsvFile $compPattern) | ForEach-Object { $sourceComputers += Import-CsvSafe $_ }
                }
            }
        }

        # Load target objects
        $targetDomainDir = Join-Path $TargetRunRoot '20_domains'
        if (Test-Path -LiteralPath $targetDomainDir) {
            Get-ChildItem -Path $targetDomainDir -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
                $domainFolder = $_.FullName

                $userPattern = Join-Path $domainFolder 'AD__Domain__Identity__Users__*.csv'
                @(Find-CsvFile $userPattern) | ForEach-Object { $targetUsers += Import-CsvSafe $_ }

                $groupPattern = Join-Path $domainFolder 'AD__Domain__Identity__Groups__*.csv'
                @(Find-CsvFile $groupPattern) | ForEach-Object { $targetGroups += Import-CsvSafe $_ }

                $compPattern = Join-Path $domainFolder 'AD__Domain__Identity__ComputersAll__*.csv'
                @(Find-CsvFile $compPattern) | ForEach-Object { $targetComputers += Import-CsvSafe $_ }
            }
        }

        # Tag environment
        $sourceUsers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
        $sourceGroups | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
        $sourceComputers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
        $targetUsers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }
        $targetGroups | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }
        $targetComputers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }

        # Combine
        $allUsers = @($sourceUsers) + @($targetUsers)
        $allGroups = @($sourceGroups) + @($targetGroups)
        $allComputers = @($sourceComputers) + @($targetComputers)

        # Run duplicate check only if data exists
        if ($allUsers.Count -gt 0 -or $allGroups.Count -gt 0 -or $allComputers.Count -gt 0) {
            $dupParams = @{
                AllUsers     = @($allUsers)
                AllGroups    = @($allGroups)
                AllComputers = @($allComputers)
            }

            if ($ExcludeBuiltIn) { $dupParams['ExcludeBuiltIn'] = $true }
            $duplicates = Get-AdDuplicateObjectsCrossForest @dupParams

            # Filter to cross-forest only (where ConflictingDomains contains both source and target)
            $crossForestDuplicates = @($duplicates | Where-Object {
                    ($_.ConflictingDomains -match ';') -or
                    ($_.ConflictCount -gt 1)
                })

            if ($crossForestDuplicates.Count -gt 0) {
                $exportColumns = $crossForestDuplicates[0].PSObject.Properties.Name | Where-Object { $_ -notin @('Severity', 'Recommendations', 'Recommendation') }
                $crossForestDuplicates |
                Select-Object -Property $exportColumns |
                Export-Csv -Path $duplicatePath -NoTypeInformation -Force
                Write-Host "  [OK] Cross-forest duplicates: $duplicatePath ($($crossForestDuplicates.Count) conflicts)" -ForegroundColor Yellow
            } else {
                Write-Host "  [OK] No cross-forest duplicate objects detected" -ForegroundColor Green
            }
        } else {
            Write-Host "  [OK] No user/group/computer data found to analyze" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Duplicate object analysis failed: $($_.Exception.Message) [Stack: $($_.ScriptStackTrace)]"
        $crossForestDuplicates = @()
    }
    Write-Host ""

    # ========================================
    # Step 6: Generate migration planning report
    # ========================================
    Write-Host "[5/5] Generating migration planning report..." -ForegroundColor Yellow
    try {
        $planningReport = New-AdMigrationPlanningReport -DiscoveryOutputPath $SourceRunRoot[0] -OutputPath $planningPath
        Write-Host "  [OK] Planning report (source): $planningPath" -ForegroundColor Green
    } catch {
        Write-Warning "Planning report failed: $_"
        $planningReport = $null
    }

    if ($IncludeTargetPlanning) {
        $targetPlanningPath = Join-Path $OutputRoot "AD__Migration__Planning__Report__Target.html"
        try {
            $targetPlanningReport = New-AdMigrationPlanningReport -DiscoveryOutputPath $TargetRunRoot -OutputPath $targetPlanningPath
            Write-Host "  [OK] Planning report (target): $targetPlanningPath" -ForegroundColor Green
        } catch {
            Write-Warning "Target planning report failed: $_"
        }
    }
    Write-Host ""

    # ========================================
    # Summary
    # ========================================
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "[COMPLETE] Analysis Complete" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "OUTPUTS GENERATED:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Assessment Reports:" -ForegroundColor Yellow
    if ($sourceAssessmentPaths.Count -gt 1) {
        Write-Host "  Source Assessments ($($sourceAssessmentPaths.Count) forests):" -ForegroundColor White
        foreach ($path in $sourceAssessmentPaths) {
            Write-Host "    - $path" -ForegroundColor Gray
        }
    } elseif ($sourceAssessmentPaths.Count -eq 1) {
        Write-Host "  - Source: $($sourceAssessmentPaths[0])" -ForegroundColor White
    }
    Write-Host "  - Target: $targetAssessmentPath" -ForegroundColor White
    Write-Host ""
    Write-Host "Comprehensive Assessments:" -ForegroundColor Yellow
    if ($sourceComprehensivePaths.Count -gt 1) {
        Write-Host "  Source Comprehensive ($($sourceComprehensivePaths.Count) forests):" -ForegroundColor White
        foreach ($path in $sourceComprehensivePaths) {
            Write-Host "    - $path" -ForegroundColor Gray
        }
    } elseif ($sourceComprehensivePaths.Count -eq 1) {
        Write-Host "  - Source: $($sourceComprehensivePaths[0])" -ForegroundColor White
    }
    Write-Host "  - Target: $targetComprehensivePath" -ForegroundColor White
    Write-Host ""
    Write-Host "Comparison:" -ForegroundColor Yellow
    Write-Host "  - Environment Comparison: $comparisonPath" -ForegroundColor White
    if ($crossForestDuplicates.Count -gt 0) {
        Write-Host "  - Cross-Forest Duplicates: $duplicatePath ($($crossForestDuplicates.Count) conflicts)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Planning:" -ForegroundColor Yellow
    Write-Host "  - Planning Report (Source): $planningPath" -ForegroundColor White
    Write-Host ""

    # Open reports if requested
    if ($OpenReports) {
        Write-Host "Opening key reports..." -ForegroundColor Yellow
        if (Test-Path -LiteralPath $comparisonPath) {
            Invoke-Item -LiteralPath $comparisonPath
        }
        if (Test-Path -LiteralPath $checklistPath) {
            Start-Sleep -Seconds 2
            Invoke-Item -LiteralPath $checklistPath
        }
    }

    return [pscustomobject]@{
        OutputRoot                    = $OutputRoot
        SourceAssessment              = $sourceAssessmentPath
        SourceComprehensiveAssessment = $sourceComprehensivePaths
        TargetAssessment              = $targetAssessmentPath
        TargetComprehensiveAssessment = $targetComprehensivePath
        ComparisonReport              = $comparisonPath
        CrossForestDuplicates         = if ($crossForestDuplicates.Count -gt 0) { $duplicatePath } else { $null }
        PlanningReport                = $planningPath
        DuplicateConflictCount        = $crossForestDuplicates.Count
    }
}
