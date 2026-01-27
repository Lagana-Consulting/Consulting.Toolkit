function Invoke-AdDiscoveryAnalysis {
    <#
    .SYNOPSIS
    Analyze pre-collected AD discovery data and generate assessment/migration reports.

    .DESCRIPTION
    Performs offline analysis of discovery data collected from source and target environments.
    Reads CSV files from discovery run folders and generates:
    - Source and target assessment reports (HTML)
    - Migration planning report
    - LOE estimation workbook
    - Environment comparison HTML
    - Migration readiness checklist
    - Cross-forest duplicate object analysis

    No Active Directory queries are performed—all analysis uses previously collected CSV data.

    .PARAMETER ConfigFile
    Path to JSON configuration file containing run roots and analysis settings.

    .PARAMETER SourceRunRoot
    Path to source environment discovery output folder

    .PARAMETER TargetRunRoot
    Path to target environment discovery output folder

    .PARAMETER CustomerName
    Customer name for report headers

    .PARAMETER OutputRoot
    Root folder for analysis outputs

    .PARAMETER GenerateLoeForBoth
    Generate LOE workbooks for both source and target

    .PARAMETER IncludeTargetPlanning
    Generate migration planning report for target environment

    .PARAMETER OpenReports
    Automatically open generated reports

    .EXAMPLE
    Invoke-AdDiscoveryAnalysis -ConfigFile "c:\analysis\config.json"
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
    $sourceAssessmentPath = Join-Path $OutputRoot "LC__Assessment__Report__Source.html"
    $targetAssessmentPath = Join-Path $OutputRoot "LC__Assessment__Report__Target.html"
    $targetComprehensivePath = Join-Path $OutputRoot "LC__Comprehensive__Assessment__Target.html"
    $comparisonPath = Join-Path $OutputRoot "LC__Environment__Comparison__Report.html"
    $checklistPath = Join-Path $OutputRoot "LC__Migration__Readiness__Checklist.html"
    $duplicatePath = Join-Path $OutputRoot "LC__Duplicate__Objects__Cross_Forest.csv"
    $planningPath = Join-Path $OutputRoot "LC__Migration__Planning__Report__Source.html"
    $loePathSource = Join-Path $OutputRoot "LC__Migration__LOE__Source.xlsx"
    $loePathTarget = Join-Path $OutputRoot "LC__Migration__LOE__Target.xlsx"

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
    Write-Host "[1/7] Generating source environment assessments..." -ForegroundColor Yellow
    $assessmentSources = @()
    $sourceAssessmentPaths = @()
    $sourceComprehensivePaths = @()

    foreach ($srcRoot in $SourceRunRoot) {
        # Extract forest/domain prefix from path
        $pathParts = Split-Path -Path $srcRoot -Leaf
        $prefix = if ($pathParts -match '^([A-Za-z0-9_]+)') { $matches[1] } else { "Source" }

        # Generate per-source assessment with suffix
        $srcAssessmentPath = Join-Path $OutputRoot "LC__Assessment__Report__Source__$prefix.html"
        $srcComprehensivePath = Join-Path $OutputRoot "LC__Comprehensive__Assessment__Source__$prefix.html"

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
    Write-Host "[2/7] Generating target environment assessment..." -ForegroundColor Yellow
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
    Write-Host "[3/7] Generating environment comparison report..." -ForegroundColor Yellow
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
    Write-Host "[4/7] Generating migration readiness checklist..." -ForegroundColor Yellow
    try {
        $readinessChecklist = New-AdMigrationReadinessChecklist -SourceRunRoot $SourceRunRoot[0] -TargetRunRoot $TargetRunRoot -OutputPath $checklistPath -CustomerName $CustomerName
        Write-Host "  [OK] Readiness checklist: $checklistPath" -ForegroundColor Green
    } catch {
        Write-Warning "Readiness checklist failed: $_"
        $readinessChecklist = $null
    }
    Write-Host ""

    # ========================================
    # Step 5: Cross-forest duplicate object analysis
    # ========================================
    Write-Host "[5/7] Analyzing cross-forest duplicate objects..." -ForegroundColor Yellow
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

                    $userPattern = Join-Path $domainFolder 'LC__AD__Domain__Identity__Users__*.csv'
                    @(Find-CsvFile $userPattern) | ForEach-Object { $sourceUsers += Import-CsvSafe $_ }

                    $groupPattern = Join-Path $domainFolder 'LC__AD__Domain__Identity__Groups__*.csv'
                    @(Find-CsvFile $groupPattern) | ForEach-Object { $sourceGroups += Import-CsvSafe $_ }

                    $compPattern = Join-Path $domainFolder 'LC__AD__Domain__Identity__ComputersAll__*.csv'
                    @(Find-CsvFile $compPattern) | ForEach-Object { $sourceComputers += Import-CsvSafe $_ }
                }
            }
        }

        # Load target objects
        $targetDomainDir = Join-Path $TargetRunRoot '20_domains'
        if (Test-Path -LiteralPath $targetDomainDir) {
            Get-ChildItem -Path $targetDomainDir -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
                $domainFolder = $_.FullName

                $userPattern = Join-Path $domainFolder 'LC__AD__Domain__Identity__Users__*.csv'
                @(Find-CsvFile $userPattern) | ForEach-Object { $targetUsers += Import-CsvSafe $_ }

                $groupPattern = Join-Path $domainFolder 'LC__AD__Domain__Identity__Groups__*.csv'
                @(Find-CsvFile $groupPattern) | ForEach-Object { $targetGroups += Import-CsvSafe $_ }

                $compPattern = Join-Path $domainFolder 'LC__AD__Domain__Identity__ComputersAll__*.csv'
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

            $duplicates = Get-AdDuplicateObjectsForAdmt @dupParams

            # Filter to cross-forest only (where ConflictingDomains contains both source and target)
            $crossForestDuplicates = @($duplicates | Where-Object {
                    ($_.ConflictingDomains -match ';') -or
                    ($_.ConflictCount -gt 1)
                })

            if ($crossForestDuplicates.Count -gt 0) {
                $crossForestDuplicates | Export-Csv -Path $duplicatePath -NoTypeInformation -Force
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
    Write-Host "[6/7] Generating migration planning report..." -ForegroundColor Yellow
    try {
        $planningReport = New-AdMigrationPlanningReport -DiscoveryOutputPath $SourceRunRoot[0] -OutputPath $planningPath
        Write-Host "  [OK] Planning report (source): $planningPath" -ForegroundColor Green
    } catch {
        Write-Warning "Planning report failed: $_"
        $planningReport = $null
    }

    if ($IncludeTargetPlanning) {
        $targetPlanningPath = Join-Path $OutputRoot "LC__Migration__Planning__Report__Target.html"
        try {
            $targetPlanningReport = New-AdMigrationPlanningReport -DiscoveryOutputPath $TargetRunRoot -OutputPath $targetPlanningPath
            Write-Host "  [OK] Planning report (target): $targetPlanningPath" -ForegroundColor Green
        } catch {
            Write-Warning "Target planning report failed: $_"
        }
    }
    Write-Host ""

    # ========================================
    # Step 7: Generate LOE workbook
    # ========================================
    Write-Host "[7/7] Generating LOE estimation workbook..." -ForegroundColor Yellow

    # Auto-detect target domain name from target discovery data
    $targetDomainName = 'TBD'
    $targetAssessmentFile = Get-ChildItem -Path $TargetRunRoot -Filter '*Assessment__Summary__Forest.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($targetAssessmentFile) {
        $targetAssessment = Import-Csv $targetAssessmentFile.FullName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($targetAssessment.ForestName) {
            $targetDomainName = $targetAssessment.ForestName
        }
    }

    try {
        $loeExcelSource = New-AdMigrationLoeExcel -SourceDiscoveryPaths $SourceRunRoot -OutputPath $loePathSource -CustomerName $CustomerName -TargetDomain $targetDomainName -TargetDiscoveryPath $TargetRunRoot
        Write-Host "  [OK] LOE workbook (source): $loePathSource" -ForegroundColor Green
    } catch {
        Write-Warning "LOE workbook failed: $_"
        $loeExcelSource = $null
    }

    if ($GenerateLoeForBoth) {
        try {
            $loeExcelTarget = New-AdMigrationLoeExcel -DiscoveryOutputPath $TargetRunRoot -OutputPath $loePathTarget -CustomerName $CustomerName
            Write-Host "  [OK] LOE workbook (target): $loePathTarget" -ForegroundColor Green
        } catch {
            Write-Warning "Target LOE workbook failed: $_"
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
    Write-Host "Comparison & Readiness:" -ForegroundColor Yellow
    Write-Host "  - Environment Comparison: $comparisonPath" -ForegroundColor White
    Write-Host "  - Readiness Checklist: $checklistPath" -ForegroundColor White
    if ($crossForestDuplicates.Count -gt 0) {
        Write-Host "  - Cross-Forest Duplicates: $duplicatePath ($($crossForestDuplicates.Count) conflicts)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Planning & LOE:" -ForegroundColor Yellow
    Write-Host "  - Planning Report (Source): $planningPath" -ForegroundColor White
    Write-Host "  - LOE Workbook (Source): $loePathSource" -ForegroundColor White
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
        ReadinessChecklist            = $checklistPath
        CrossForestDuplicates         = if ($crossForestDuplicates.Count -gt 0) { $duplicatePath } else { $null }
        PlanningReport                = $planningPath
        LoeWorkbook                   = $loePathSource
        DuplicateConflictCount        = $crossForestDuplicates.Count
    }
}
