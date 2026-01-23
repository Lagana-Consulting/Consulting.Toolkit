function New-LcMigrationLoeExcel {
    <#
    .SYNOPSIS
    Generate a detailed Excel workbook for migration LOE estimation.
    Uses ImportExcel module for robust Excel operations.
    Supports single or multiple source discovery paths.

    .PARAMETER DiscoveryOutputPath
    Path to a single discovery output folder (for backward compatibility).
    Use SourceDiscoveryPaths for multiple sources.

    .PARAMETER SourceDiscoveryPaths
    Array of discovery output folders for multiple source forests/domains.
    Preferred over DiscoveryOutputPath when aggregating multiple sources.

    .PARAMETER OutputPath
    Optional path for the resulting Excel file. Defaults inside first source path.

    .PARAMETER CustomerName
    Customer name for the workbook title.

    .PARAMETER TargetDomain
    Target domain name for migration (defaults to 'TBD').

    .PARAMETER TargetDiscoveryPath
    Path to target discovery output folder (optional).
    #>
    [CmdletBinding()]
    param(
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$DiscoveryOutputPath,

        [ValidateScript({
                foreach ($p in $_) {
                    if (-not (Test-Path $p -PathType Container)) {
                        throw "Path not found: $p"
                    }
                }
                $true
            })]
        [string[]]$SourceDiscoveryPaths,

        [string]$OutputPath,

        [string]$CustomerName = "TBD",

        [string]$TargetDomain = "TBD",

        [string]$TargetDiscoveryPath
    )

    # Normalize to array of source paths
    if ($SourceDiscoveryPaths) {
        $sourcePaths = $SourceDiscoveryPaths
    } elseif ($DiscoveryOutputPath) {
        $sourcePaths = @($DiscoveryOutputPath)
    } else {
        throw "Must provide either DiscoveryOutputPath or SourceDiscoveryPaths"
    }

    # Helper to safely import CSV
    function _imp($p) {
        if (-not $p) { return @() }
        if (Test-Path $p -ErrorAction SilentlyContinue) {
            try { return @(Import-Csv $p) } catch { return @() }
        }
        return @()
    }

    # Load discovery data from all source paths
    $domainDirs = @()
    $totalEnabledUsers = 0
    $totalActiveWorkstations = 0
    $totalServers = 0
    $totalGroups = 0
    $totalGpos = 0
    $domainMetrics = @()

    # Collect domain directories from all source paths
    foreach ($srcPath in $sourcePaths) {
        $domains20 = Join-Path $srcPath '20_domains'
        if (Test-Path $domains20) {
            $domainDirs += (Get-ChildItem -Path $domains20 -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Domain-' })
        }
    }

    # Auto-detect target domain from first source if not specified
    if ($TargetDomain -eq 'TBD') {
        $assessmentFile = Get-ChildItem -Path $sourcePaths[0] -Filter '*Assessment__Summary__Forest.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($assessmentFile) {
            $assessment = _imp($assessmentFile.FullName) | Select-Object -First 1
            if ($assessment.ForestName) {
                $TargetDomain = $assessment.ForestName
                Write-Verbose "Auto-detected target domain: $TargetDomain"
            }
        }
    }

    # Aggregate domain metrics from all sources
    foreach ($ddir in $domainDirs) {
        $domainName = $ddir.Name -replace '^Domain-', ''

        $usersFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__Users*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $users = if ($usersFile) { _imp($usersFile.FullName) } else { @() }
        $enabledUsers = @($users | Where-Object { $_.Enabled -eq 'True' }).Count

        $computersFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__ComputersAll*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $computers = if ($computersFile) { _imp($computersFile.FullName) } else { @() }
        $activeWorkstations = @($computers | Where-Object {
                $_.Enabled -eq 'True' -and $_.OperatingSystem -notmatch 'Server' -and ($_.'LastLogonDays' -as [int]) -le 30
            }).Count
        $servers = @($computers | Where-Object { $_.OperatingSystem -match 'Server' }).Count

        $groupsFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__Groups*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $groups = if ($groupsFile) { _imp($groupsFile.FullName) } else { @() }
        $groupCount = @($groups).Count

        $gpoFile = Get-ChildItem -Path $ddir.FullName -Filter '*Policy__GpoInventory*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $gpos = if ($gpoFile) { _imp($gpoFile.FullName) } else { @() }
        $gpoCount = @($gpos).Count

        $dcFile = Get-ChildItem -Path $ddir.FullName -Filter '*Infrastructure__DomainControllers*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $dcs = if ($dcFile) { _imp($dcFile.FullName) } else { @() }
        $dcCount = @($dcs).Count

        $domainMetrics += @{
            Prefix             = ($domainName -split '\.' | Select-Object -First 1).ToUpper()
            Domain             = $domainName
            EnabledUsers       = $enabledUsers
            ActiveWorkstations = $activeWorkstations
            Servers            = $servers
            Groups             = $groupCount
            DCs                = $dcCount
            GPOs               = $gpoCount
            Role               = 'Source'
        }

        $totalEnabledUsers += $enabledUsers
        $totalActiveWorkstations += $activeWorkstations
        $totalServers += $servers
        $totalGroups += $groupCount
        $totalGpos += $gpoCount
    }

    # Optionally append target domain metrics (do not change source totals)
    if ($TargetDiscoveryPath -and (Test-Path -LiteralPath $TargetDiscoveryPath)) {
        $tDomains20 = Join-Path $TargetDiscoveryPath '20_domains'
        $tDomainDirs = @()
        foreach ($root in @($TargetDiscoveryPath, $tDomains20)) {
            if (Test-Path $root) {
                $tDomainDirs += (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Domain-' })
            }
        }
        $tDomainDirs = $tDomainDirs | Sort-Object -Property FullName -Unique

        foreach ($tdd in $tDomainDirs) {
            $tDomainName = $tdd.Name -replace '^Domain-', ''

            $tUsersFile = Get-ChildItem -Path $tdd.FullName -Filter '*Identity__Users*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $tUsers = if ($tUsersFile) { _imp($tUsersFile.FullName) } else { @() }
            $tEnabledUsers = @($tUsers | Where-Object { $_.Enabled -eq 'True' }).Count

            $tComputersFile = Get-ChildItem -Path $tdd.FullName -Filter '*Identity__ComputersAll*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $tComputers = if ($tComputersFile) { _imp($tComputersFile.FullName) } else { @() }
            $tActiveWorkstations = @($tComputers | Where-Object { $_.Enabled -eq 'True' -and $_.OperatingSystem -notmatch 'Server' -and ($_.'LastLogonDays' -as [int]) -le 30 }).Count
            $tServers = @($tComputers | Where-Object { $_.OperatingSystem -match 'Server' }).Count

            $tGroupsFile = Get-ChildItem -Path $tdd.FullName -Filter '*Identity__Groups*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $tGroups = if ($tGroupsFile) { _imp($tGroupsFile.FullName) } else { @() }
            $tGroupCount = @($tGroups).Count

            $tDcFile = Get-ChildItem -Path $tdd.FullName -Filter '*Infrastructure__DomainControllers*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $tDcs = if ($tDcFile) { _imp($tDcFile.FullName) } else { @() }
            $tDcCount = @($tDcs).Count

            $tGpoFile = Get-ChildItem -Path $tdd.FullName -Filter '*Policy__GpoInventory*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $tGpos = if ($tGpoFile) { _imp($tGpoFile.FullName) } else { @() }
            $tGpoCount = @($tGpos).Count

            $domainMetrics += @{
                Prefix             = ($tDomainName -split '\.' | Select-Object -First 1).ToUpper()
                Domain             = $tDomainName
                EnabledUsers       = $tEnabledUsers
                ActiveWorkstations = $tActiveWorkstations
                Servers            = $tServers
                Groups             = $tGroupCount
                DCs                = $tDcCount
                GPOs               = $tGpoCount
                Role               = 'Target'
            }
        }
    }

    # Load duplicate conflicts from first source
    $dupFile = Get-ChildItem $sourcePaths[0] -Filter '*Duplicate__Objects__Cross_Forest*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dupFile) {
        $forest10 = Join-Path $sourcePaths[0] '10_forest'
        $dupFile = Get-ChildItem $forest10 -Filter '*DuplicateObjectsForAdmt*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $duplicates = if ($dupFile) { _imp($dupFile.FullName) } else { @() }
    $userConflicts = @($duplicates | Where-Object { $_.ObjectClasses -match 'user' }).Count
    $groupConflicts = @($duplicates | Where-Object { $_.ObjectClasses -match 'group' }).Count
    $computerConflicts = @($duplicates | Where-Object { $_.ObjectClasses -match 'computer' }).Count
    $totalConflicts = $userConflicts + $groupConflicts + $computerConflicts
    $conflictAdderHours = [math]::Round($totalConflicts * 0.1, 1)

    # Default output path to first source
    if (-not $OutputPath) {
        $ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $OutputPath = Join-Path $sourcePaths[0] "$CustomerName`_AD_Migration_LOE_Calculator_$ts.xlsx"
    }

    # Calculate LOE line items
    $loeCalculatorData = @(
        @{ Category = 'Discovery - Review AD assessments'; Count = 1; HrsUnit = 6; Comments = 'Review existing AD assessments and inventories.' }
        @{ Category = 'Discovery - Validate trusts/DNS/object readiness'; Count = 1; HrsUnit = 6; Comments = 'Validate trusts, DNS, and object readiness across domains.' }
        @{ Category = 'Design - Validate target OU readiness'; Count = 1; HrsUnit = 4; Comments = 'Validate target OU structure, delegation, and placement.' }
        @{ Category = 'Design - GPO planning (review source GPOs; create new as needed)'; Count = $totalGpos; HrsUnit = 0.2; Comments = 'GPOs not migrated; review and create required equivalents.' }
        @{ Category = 'Design - Naming conflicts remediation planning'; Count = $totalConflicts; HrsUnit = 0.1; Comments = "Name conflicts ($userConflicts users, $groupConflicts groups, $computerConflicts computers) drive decisions." }
        @{ Category = 'Migration - User migrations (source domains)'; Count = $totalEnabledUsers; HrsUnit = 0.15; Comments = 'Enabled users in source domains to migrate.' }
        @{ Category = 'Migration - Group migrations (source domains)'; Count = $totalGroups; HrsUnit = 0.05; Comments = 'Groups in source domains to migrate as needed.' }
        @{ Category = 'Migration - Workstation migrations (active; source domains)'; Count = $totalActiveWorkstations; HrsUnit = 0.25; Comments = 'Active workstations in source domains to migrate.' }
        @{ Category = 'Migration - Server migrations (identity-only; source domains)'; Count = $totalServers; HrsUnit = 0.1; Comments = 'Servers in source domains (identity-only unless scoped).' }
        @{ Category = 'Post - Access validation & remediation'; Count = ($totalEnabledUsers + $totalGroups); HrsUnit = 0.05; Comments = 'Validate user logon + resource access; remediation buffer.' }
        @{ Category = 'Post - Legacy domain decommissioning support'; Count = @($domainMetrics).Count; HrsUnit = 2; Comments = 'Decommissioning support per legacy source domain.' }
    )

    # Calculate totals for reference (used in other sheets)
    $totalLoeHours = 0
    foreach ($item in $loeCalculatorData) {
        $totalLoeHours += [math]::Round($item.Count * $item.HrsUnit, 1)
    }

    Write-Verbose "Creating Excel workbook: $OutputPath with formulas"

    # Remove existing file if it exists
    if (Test-Path $OutputPath) {
        Remove-Item $OutputPath -Force
    }

    # Create workbook and build LOE Calculator sheet with formulas
    $excel = Open-ExcelPackage -Create -Path $OutputPath

    try {
        # ===== Sheet 1: LOE Calculator (with formulas) =====
        $wsCalc = $excel.Workbook.Worksheets.Add('LOE Calculator')
        Write-Verbose ("wsCalc.Cells type: " + ($wsCalc.Cells.GetType().FullName))

        # Headers
        $wsCalc.Cells['A1'].Value = 'Category'
        $wsCalc.Cells['B1'].Value = 'Count'
        $wsCalc.Cells['C1'].Value = 'Hours/Unit'
        $wsCalc.Cells['D1'].Value = 'Total Hours'

        $row = 2
        foreach ($item in $loeCalculatorData) {
            $wsCalc.Cells["A$row"].Value = $item.Category
            $wsCalc.Cells["B$row"].Value = $item.Count
            $wsCalc.Cells["C$row"].Value = $item.HrsUnit
            # Formula: =B2*C2 (Count * Hours/Unit)
            $wsCalc.Cells["D$row"].Formula = "=B$row*C$row"
            $wsCalc.Cells["E$row"].Value = $item.Comments
            $row++
        }

        # Total row with SUM formula
        $lastDataRow = $row - 1
        $wsCalc.Cells["A$row"].Value = 'TOTAL'
        $wsCalc.Cells["A$row"].Style.Font.Bold = $true
        $wsCalc.Cells["B$row"].Value = ''
        $wsCalc.Cells["C$row"].Value = ''
        # Formula: =SUM(D2:D12)
        $wsCalc.Cells["D$row"].Formula = "=SUM(D2:D$lastDataRow)"
        $wsCalc.Cells["D$row"].Style.Font.Bold = $true
        $wsCalc.Cells["E$row"].Value = ''

        $wsCalc.Cells[$wsCalc.Dimension.Address].AutoFitColumns()

        # ===== Sheet 2: LOE by Phase (with formulas) =====
        # ===== Sheet 2: LOE by Phase (with formulas) =====
        # Map phase names to row ranges in LOE Calculator sheet
        $phaseMapping = @{
            'Discovery & Validation' = @(2, 3)   # Rows 2-3
            'Design & Planning'      = @(4, 6)   # Rows 4-6
            'Migration Execution'    = @(7, 10)  # Rows 7-10
            'Post-Migration'         = @(11, 12) # Rows 11-12
        }

        $wsPhase = $excel.Workbook.Worksheets.Add('LOE by Phase')
        $row = 1
        $wsPhase.Cells.Item($row, 1).Value = 'Phase'
        $wsPhase.Cells.Item($row, 2).Value = 'Total Hours'
        $wsPhase.Cells.Item($row, 3).Value = 'Notes'
        $wsPhase.Cells.Item($row, 1).Style.Font.Bold = $true
        $wsPhase.Cells.Item($row, 2).Style.Font.Bold = $true
        $wsPhase.Cells.Item($row, 3).Style.Font.Bold = $true

        $row = 2
        foreach ($phase in @('Discovery & Validation', 'Design & Planning', 'Migration Execution', 'Post-Migration')) {
            $wsPhase.Cells.Item($row, 1).Value = $phase
            $startRow = $phaseMapping[$phase][0]
            $endRow = $phaseMapping[$phase][1]
            # Formula: =SUM('LOE Calculator'!D2:D3)
            $wsPhase.Cells.Item($row, 2).Formula = "=SUM('LOE Calculator'!D$($startRow):D$($endRow))"
            $wsPhase.Cells.Item($row, 3).Value = 'Derived from LOE Calculator'
            $row++
        }

        # Total row with formula
        $wsPhase.Cells.Item($row, 1).Value = 'TOTAL'
        $wsPhase.Cells.Item($row, 1).Style.Font.Bold = $true
        # Formula: =SUM(B2:B5)
        $wsPhase.Cells.Item($row, 2).Formula = "=SUM(B2:B$($row-1))"
        $wsPhase.Cells.Item($row, 2).Style.Font.Bold = $true
        $wsPhase.Cells.Item($row, 3).Value = ''

        # Add pricing section with formulas
        $totalHoursRow = $row
        $row += 2
        $wsPhase.Cells.Item($row, 1).Value = 'Pricing'
        $wsPhase.Cells.Item($row, 1).Style.Font.Bold = $true
        $row++
        $wsPhase.Cells.Item($row, 1).Value = 'T&M Rate (per hour)'
        $wsPhase.Cells.Item($row, 2).Value = 0
        $rateRow = $row
        $row++
        $wsPhase.Cells.Item($row, 1).Value = 'Fixed Fee Multiplier'
        $wsPhase.Cells.Item($row, 2).Value = 1.15
        $multiplierRow = $row
        $row++
        $wsPhase.Cells.Item($row, 1).Value = 'T&M Estimated Cost'
        # Formula: =B6*B8 (Total Hours * T&M Rate)
        $wsPhase.Cells.Item($row, 2).Formula = "=B$totalHoursRow*B$rateRow"
        $tmCostRow = $row
        $row++
        $wsPhase.Cells.Item($row, 1).Value = 'Fixed Fee Price'
        # Formula: =B10*B9 (T&M Cost * Multiplier)
        $wsPhase.Cells.Item($row, 2).Formula = "=B$tmCostRow*B$multiplierRow"

        $wsPhase.Cells[$wsPhase.Dimension.Address].AutoFitColumns()

        # ===== Sheet 3: Executive Summary (with formulas) =====
        $wsExec = $excel.Workbook.Worksheets.Add('Executive Summary')

        $row = 1
        $wsExec.Cells.Item($row, 1).Value = 'Executive LOE Summary'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true
        $wsExec.Cells.Item($row, 1).Style.Font.Size = 14

        $row = 3
        $wsExec.Cells.Item($row, 1).Value = 'Project / Customer'
        $wsExec.Cells.Item($row, 2).Value = $CustomerName
        $row++
        $wsExec.Cells.Item($row, 1).Value = 'Target Domain'
        $wsExec.Cells.Item($row, 2).Value = $TargetDomain
        $row++
        $wsExec.Cells.Item($row, 1).Value = 'Source Domains'
        $sourceDomains = ($domainMetrics | ForEach-Object { $_['Domain'] }) -join ', '
        $wsExec.Cells.Item($row, 2).Value = if ($sourceDomains) { $sourceDomains } else { 'TBD' }
        $row++
        $wsExec.Cells.Item($row, 1).Value = 'Report Date'
        $wsExec.Cells.Item($row, 2).Value = (Get-Date).ToString('yyyy-MM-dd')

        $row = 8
        $wsExec.Cells.Item($row, 1).Value = 'Environment Snapshot'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true

        $row = 9
        $wsExec.Cells.Item($row, 1).Value = 'Metric'
        $wsExec.Cells.Item($row, 2).Value = 'Value'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true
        $wsExec.Cells.Item($row, 2).Style.Font.Bold = $true

        $metrics = @(
            @('Enabled Users', $totalEnabledUsers),
            @('Active Workstations', $totalActiveWorkstations),
            @('Servers', $totalServers),
            @('Total Groups', $totalGroups),
            @('Name Conflicts', $totalConflicts),
            @('Conflict LOE Adder (hrs)', $conflictAdderHours)
        )

        $row = 10
        foreach ($m in $metrics) {
            $wsExec.Cells.Item($row, 1).Value = $m[0]
            $wsExec.Cells.Item($row, 2).Value = $m[1]
            $row++
        }

        $row += 1
        $wsExec.Cells.Item($row, 1).Value = 'LOE Summary by Phase'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true
        $row++
        $wsExec.Cells.Item($row, 1).Value = 'Phase'
        $wsExec.Cells.Item($row, 2).Value = 'Hours'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true
        $wsExec.Cells.Item($row, 2).Style.Font.Bold = $true

        $row++
        $phaseStartRow = $row
        foreach ($phase in @('Discovery & Validation', 'Design & Planning', 'Migration Execution', 'Post-Migration')) {
            $wsExec.Cells.Item($row, 1).Value = $phase
            # Formula: ='LOE by Phase'!B2 (reference phase sheet)
            $phaseRow = $row - $phaseStartRow + 2
            $wsExec.Cells.Item($row, 2).Formula = "='LOE by Phase'!B$phaseRow"
            $row++
        }
        $wsExec.Cells.Item($row, 1).Value = 'TOTAL'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true
        # Formula: ='LOE by Phase'!B6 (reference phase total)
        $wsExec.Cells.Item($row, 2).Formula = "='LOE by Phase'!B6"
        $wsExec.Cells.Item($row, 2).Style.Font.Bold = $true

        # Add Environment Snapshot (by Domain) section
        $row += 2
        $wsExec.Cells.Item($row, 1).Value = 'Environment Snapshot (by Domain)'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true

        $row++
        $wsExec.Cells.Item($row, 1).Value = 'Prefix'
        $wsExec.Cells.Item($row, 2).Value = 'Domain'
        $wsExec.Cells.Item($row, 3).Value = 'Enabled Users'
        $wsExec.Cells.Item($row, 4).Value = 'Active Workstations'
        $wsExec.Cells.Item($row, 5).Value = 'Servers'
        $wsExec.Cells.Item($row, 6).Value = 'Groups'
        $wsExec.Cells.Item($row, 7).Value = 'DCs'
        $wsExec.Cells.Item($row, 8).Value = 'GPOs'
        $wsExec.Cells.Item($row, 9).Value = 'Role'
        for ($col = 1; $col -le 9; $col++) {
            $wsExec.Cells.Item($row, $col).Style.Font.Bold = $true
        }

        $row++
        $domainStartRow = $row
        foreach ($dm in $domainMetrics) {
            $wsExec.Cells.Item($row, 1).Value = $dm['Prefix']
            $wsExec.Cells.Item($row, 2).Value = $dm['Domain']
            $wsExec.Cells.Item($row, 3).Value = $dm['EnabledUsers']
            $wsExec.Cells.Item($row, 4).Value = $dm['ActiveWorkstations']
            $wsExec.Cells.Item($row, 5).Value = $dm['Servers']
            $wsExec.Cells.Item($row, 6).Value = $dm['Groups']
            $wsExec.Cells.Item($row, 7).Value = $dm['DCs']
            $wsExec.Cells.Item($row, 8).Value = $dm['GPOs']
            $wsExec.Cells.Item($row, 9).Value = $dm['Role']
            $row++
        }

        # TOTAL row for domain snapshot
        $domainEndRow = $row - 1
        $wsExec.Cells.Item($row, 1).Value = 'TOTAL'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true
        $wsExec.Cells.Item($row, 3).Formula = "=SUM(C$($domainStartRow):C$domainEndRow)"
        $wsExec.Cells.Item($row, 4).Formula = "=SUM(D$($domainStartRow):D$domainEndRow)"
        $wsExec.Cells.Item($row, 5).Formula = "=SUM(E$($domainStartRow):E$domainEndRow)"
        $wsExec.Cells.Item($row, 6).Formula = "=SUM(F$($domainStartRow):F$domainEndRow)"
        $wsExec.Cells.Item($row, 7).Formula = "=SUM(G$($domainStartRow):G$domainEndRow)"
        $wsExec.Cells.Item($row, 8).Formula = "=SUM(H$($domainStartRow):H$domainEndRow)"
        for ($col = 3; $col -le 8; $col++) {
            $wsExec.Cells.Item($row, $col).Style.Font.Bold = $true
        }

        # Add Key Assumptions / Notes section
        $row += 2
        $wsExec.Cells.Item($row, 1).Value = 'Key Assumptions / Notes'
        $wsExec.Cells.Item($row, 1).Style.Font.Bold = $true

        $row++
        $assumptions = @(
            "• Target domain exists; UPN suffix standardized in target.",
            "• GPO approach: create new GPOs as needed (inventory used for planning).",
            "• Trusts must exist prior to migration (flagged if missing).",
            "• Naming conflicts add remediation effort."
        )
        foreach ($assumption in $assumptions) {
            $wsExec.Cells.Item($row, 1).Value = $assumption
            $row++
        }

        $wsExec.Cells[$wsExec.Dimension.Address].AutoFitColumns()

        # ===== Sheet 4: Infra & Readiness =====
        $wsInfra = $excel.Workbook.Worksheets.Add('Infra & Readiness')

        $row = 1
        $wsInfra.Cells.Item($row, 1).Value = 'Domain'
        $wsInfra.Cells.Item($row, 2).Value = 'DCs'
        $wsInfra.Cells.Item($row, 3).Value = 'Baseline'
        $wsInfra.Cells.Item($row, 4).Value = 'GPOs'
        $wsInfra.Cells.Item($row, 5).Value = 'Role'
        $wsInfra.Cells.Item($row, 1).Style.Font.Bold = $true
        $wsInfra.Cells.Item($row, 2).Style.Font.Bold = $true
        $wsInfra.Cells.Item($row, 3).Style.Font.Bold = $true
        $wsInfra.Cells.Item($row, 4).Style.Font.Bold = $true
        $wsInfra.Cells.Item($row, 5).Style.Font.Bold = $true

        $row = 2
        foreach ($dm in $domainMetrics) {
            $wsInfra.Cells.Item($row, 1).Value = $dm['Domain']
            $wsInfra.Cells.Item($row, 2).Value = $dm['DCs']
            $wsInfra.Cells.Item($row, 3).Value = 2
            $wsInfra.Cells.Item($row, 4).Value = $dm['GPOs']
            $wsInfra.Cells.Item($row, 5).Value = $dm['Role']
            $row++
        }

        $wsInfra.Cells[$wsInfra.Dimension.Address].AutoFitColumns()

        # ===== Sheet 5: Assumptions =====
        $wsAssump = $excel.Workbook.Worksheets.Add('Assumptions')

        $row = 1
        $wsAssump.Cells.Item($row, 1).Value = 'LOE Assumptions (Generated by Automation)'
        $wsAssump.Cells.Item($row, 1).Style.Font.Bold = $true
        $row++
        $wsAssump.Cells.Item($row, 1).Value = 'Generated: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $row++
        $wsAssump.Cells.Item($row, 1).Value = 'Discovery Path: ' + $DiscoveryOutputPath

        $assumptions = @(
            '- Target domain is existing. Name collisions expected; UPN suffix standardized in target.',
            '- Target DC baseline: minimum 2 DCs.',
            '- GPO strategy: do not migrate GPOs; create new GPOs as required.',
            '- Trust readiness: trusts should exist between target and each source domain.',
            '- Users count = enabled users. Workstations = enabled non-server OS with recent logon.',
            '- Conflict remediation LOE adders: 0.1h per conflict for planning/communication.',
            '- Built-in AD accounts excluded from conflict detection.',
            '- Phase-based LOE model uses Base (fixed), Variable (count-driven), and Risk (adder) categories.',
            '- Fixed fee multiplier: 1.15 (15% markup over T&M for scope/risk buffer).'
        )

        $row = 5
        foreach ($a in $assumptions) {
            $wsAssump.Cells.Item($row, 1).Value = $a
            $row++
        }

        $wsAssump.Cells[$wsAssump.Dimension.Address].AutoFitColumns()

    } finally {
        Close-ExcelPackage $excel
    }

    Write-Verbose "Workbook saved to $OutputPath with 5 sheets"

    return [pscustomobject]@{
        ExcelPath          = $OutputPath
        TotalLOE           = $totalLoeHours
        EnabledUsers       = $totalEnabledUsers
        ActiveWorkstations = $totalActiveWorkstations
        Servers            = $totalServers
        Groups             = $totalGroups
        UserConflicts      = $userConflicts
        GroupConflicts     = $groupConflicts
        ComputerConflicts  = $computerConflicts
        ConflictAdderHours = $conflictAdderHours
    }
}
