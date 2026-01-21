function New-LcMigrationLoeExcel {
    <#
    .SYNOPSIS
    Generate a detailed Excel workbook for migration LOE estimation based on discovery data and JSON config.

    .PARAMETER DiscoveryOutputPath
    Path to the discovery output folder containing CSVs.

    .PARAMETER ConfigPath
    Path to LOE configuration JSON file. Defaults to module config folder.

    .PARAMETER OutputPath
    Optional path for the resulting Excel file. Defaults inside DiscoveryOutputPath.

    .PARAMETER CustomerName
    Customer name for the workbook title. Defaults to forest name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$DiscoveryOutputPath,

        [string]$ConfigPath,

        [string]$OutputPath,

        [string]$CustomerName
    )

    # Default config path (module or embedded)
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot "..\..\config\LOE.config.json"
        if (-not (Test-Path $ConfigPath)) {
            throw "LOE config not found at $ConfigPath"
        }
    }

    # Load config
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    # Load discovery data
    function _imp($p) { if (Test-Path $p) { try { @(Import-Csv $p) } catch { @() } } else { @() } }

    $forestPath = $DiscoveryOutputPath
    $forest10 = Join-Path $DiscoveryOutputPath '10_forest'
    $domains20 = Join-Path $DiscoveryOutputPath '20_domains'

    $forestSummaryFile = Get-ChildItem -Path $forestPath -Filter '*Assessment__Summary*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $forestSummaryFile) {
        $forestSummaryFile = Get-ChildItem -Path $forest10 -Filter '*Forest__Summary*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $forestSummary = @()
    if ($forestSummaryFile) { $forestSummary = @(Import-Csv $forestSummaryFile.FullName) }
    $summaryRow = if ($forestSummary.Count -gt 0) { $forestSummary[0] } else { $null }

    $forestName = if ($summaryRow) { $summaryRow.ForestName } else { "Unknown" }
    if (-not $CustomerName) { $CustomerName = $forestName }

    # Default output
    if (-not $OutputPath) {
        $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $OutputPath = Join-Path $DiscoveryOutputPath "LC__Migration__LOE__$CustomerName`__$ts.xlsx"
    }

    # Aggregate identity + complexity data
    $usersTotal = 0; $groupsTotal = 0; $computersTotal = 0
    $usersStale = 0; $computersStale = 0
    $groupNesting = @(); $ouDepth = @(); $crossDomain = @()
    $dupSpns = @(); $emptyGroups = @(); $disabled = @(); $adminSd = @(); $tokenBloat = @()
    $duplicateObjects = @()

    $domainDirs = @()
    foreach ($root in @($DiscoveryOutputPath, $domains20)) {
        if (Test-Path $root) {
            $domainDirs += (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Domain-' })
        }
    }
    $domainDirs = $domainDirs | Sort-Object -Property FullName -Unique

    foreach ($ddir in $domainDirs) {
        $usersFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__Users__*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $groupsFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__Groups__*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $computersFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__ComputersAll__*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1

        $users = if ($usersFile) { @(Import-Csv $usersFile.FullName) } else { @() }
        $groups = if ($groupsFile) { @(Import-Csv $groupsFile.FullName) } else { @() }
        $computers = if ($computersFile) { @(Import-Csv $computersFile.FullName) } else { @() }

        $usersTotal += @($users).Count
        $groupsTotal += @($groups).Count
        $computersTotal += @($computers).Count
        $usersStale += @($users | Where-Object { ($_.'LastLogonDays' -as [double]) -gt 180 }).Count
        $computersStale += @($computers | Where-Object { ($_.'LastLogonDays' -as [double]) -gt 90 }).Count

        $groupNesting += _imp((Get-ChildItem $ddir.FullName -Filter '*GroupNestingDepth*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
        $ouDepth += _imp((Get-ChildItem $ddir.FullName -Filter '*OuDepthAnalysis*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
        $crossDomain += _imp((Get-ChildItem $ddir.FullName -Filter '*CrossDomainGroupMembership*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
        $dupSpns += _imp((Get-ChildItem $ddir.FullName -Filter '*DuplicateSpns*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
        $emptyGroups += _imp((Get-ChildItem $ddir.FullName -Filter '*EmptyGroups*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
        $disabled += _imp((Get-ChildItem $ddir.FullName -Filter '*DisabledAccounts*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
        $adminSd += _imp((Get-ChildItem $ddir.FullName -Filter '*AdminSdHolderImpact*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
        $tokenBloat += _imp((Get-ChildItem $ddir.FullName -Filter '*GroupTokenBloat*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
    }

    $duplicateObjects = _imp((Get-ChildItem $forest10 -Filter '*DuplicateObjectsForAdmt*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
    $trustMap = _imp((Get-ChildItem $forest10 -Filter '*TrustRelationshipMap*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)

    # Compute metrics
    $groupsWithDeepNesting = @($groupNesting | Where-Object { ($_.'NestingDepth' -as [int]) -ge 3 }).Count
    $ouWithDeepStructure = @($ouDepth | Where-Object { ($_.'MaxDepth' -as [int]) -ge 6 }).Count
    $stalePct = if ($usersTotal -gt 0) { [math]::Round((($usersStale + $computersStale) / ($usersTotal + $computersTotal)) * 100, 1) } else { 0 }

    # Wave calculations
    $userWaves = [math]::Max(1, [math]::Ceiling($usersTotal / $config.waveDefaults.usersPerWave))
    $computerWaves = [math]::Max(1, [math]::Ceiling($computersTotal / $config.waveDefaults.computersPerWave))

    # Compute LOE per phase with multipliers
    $phaseData = @()
    foreach ($phase in $config.phases) {
        $phaseDays = 0
        $taskDetails = @()

        foreach ($task in $phase.tasks) {
            $taskDays = $task.baseDays

            # Apply multipliers
            foreach ($mult in $task.multipliers.PSObject.Properties) {
                $factor = $mult.Value
                $indicator = $mult.Name

                switch ($indicator) {
                    'domainsPerDay' { $taskDays += @($domainDirs).Count * $factor }
                    'complexityScore' { $taskDays += 50 * $factor } # Assume mid-range 50/100
                    'waveCount' { $taskDays += ($userWaves + $computerWaves) * $factor }
                    'duplicateObjectsCount' { $taskDays += @($duplicateObjects).Count * $factor }
                    'duplicateSpnsCount' { $taskDays += @($dupSpns).Count * $factor }
                    'emptyGroupsCount' { $taskDays += @($emptyGroups).Count * $factor }
                    'adminSdHolderImpactCount' { $taskDays += @($adminSd).Count * $factor }
                    'disabledAccountsCount' { $taskDays += @($disabled).Count * $factor }
                    'tokenBloatCount' { $taskDays += @($tokenBloat).Count * $factor }
                    'crossDomainGroupCount' { $taskDays += @($crossDomain).Count * $factor }
                    'usersPerWave' { $taskDays += ($usersTotal / $config.waveDefaults.usersPerWave) * $factor }
                    'computersPerWave' { $taskDays += ($computersTotal / $config.waveDefaults.computersPerWave) * $factor }
                    'waveCount' { $taskDays += ($userWaves + $computerWaves) * $factor }
                }
            }

            $taskDays = [math]::Max(0.5, [math]::Round($taskDays, 1))
            $phaseDays += $taskDays
            $taskDetails += [pscustomobject]@{
                Task  = $task.name
                Days  = $taskDays
                Notes = $task.notes
            }
        }

        $phaseData += [pscustomobject]@{
            Phase       = $phase.name
            Description = $phase.description
            Days        = [math]::Round($phaseDays, 1)
            Tasks       = $taskDetails
        }
    }

    # Apply risk multipliers
    $riskMultiplier = 1.0
    foreach ($risk in $config.riskFactors) {
        $riskValue = switch ($risk.indicator) {
            'groupsWithDeepNestingCount' { $groupsWithDeepNesting }
            'ouDepthCount' { $ouWithDeepStructure }
            'crossDomainGroupCount' { @($crossDomain).Count }
            'trustCount' { @($trustMap).Count }
            'rc4OnlyObjectsCount' { 0 } # Would need to check summary
            'stalePct' { if ($stalePct -gt 10) { 1 } else { 0 } }
            default { 0 }
        }

        if ($riskValue -gt 0) {
            $riskMultiplier *= $risk.multiplier
        }
    }

    $totalLoe = ([double]($phaseData | Measure-Object -Property Days -Sum).Sum) * $riskMultiplier
    $totalLoe = [math]::Round($totalLoe, 1)

    # Create Excel
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $workbook = $excel.Workbooks.Add()

    # Remove default sheets
    while ($workbook.Sheets.Count -gt 1) {
        $workbook.Sheets.Item($workbook.Sheets.Count).Delete()
    }

    # Worksheet 1: Executive Summary
    $ws1 = $workbook.Sheets.Item(1)
    $ws1.Name = "Executive Summary"
    $ws1.Range("A1").Value = "AD Migration - Level of Effort Estimate"
    $ws1.Range("A1").Font.Bold = $true
    $ws1.Range("A1").Font.Size = 14
    $ws1.Range("A2").Value = "Customer: $CustomerName"
    $ws1.Range("A3").Value = "Forest: $forestName"
    $ws1.Range("A4").Value = "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

    $row = 6
    $ws1.Range("A$row").Value = "Metrics"
    $ws1.Range("A$row").Font.Bold = $true
    $row++
    $ws1.Range("A$row").Value = "Users"; $ws1.Range("B$row").Value = $usersTotal; $row++
    $ws1.Range("A$row").Value = "Groups"; $ws1.Range("B$row").Value = $groupsTotal; $row++
    $ws1.Range("A$row").Value = "Computers"; $ws1.Range("B$row").Value = $computersTotal; $row++
    $ws1.Range("A$row").Value = "User Waves"; $ws1.Range("B$row").Value = $userWaves; $row++
    $ws1.Range("A$row").Value = "Computer Waves"; $ws1.Range("B$row").Value = $computerWaves; $row++

    $row += 2
    $ws1.Range("A$row").Value = "Level of Effort (Days)"
    $ws1.Range("A$row").Font.Bold = $true
    $row++
    foreach ($phase in $phaseData) {
        $ws1.Range("A$row").Value = $phase.Phase
        $ws1.Range("B$row").Value = $phase.Days
        $row++
    }
    $ws1.Range("A$row").Value = "Subtotal"
    $ws1.Range("A$row").Font.Bold = $true
    $ws1.Range("B$row").Value = [double]($phaseData | Measure-Object -Property Days -Sum).Sum
    $row++
    $ws1.Range("A$row").Value = "Risk Multiplier"
    $ws1.Range("B$row").Value = [math]::Round($riskMultiplier, 2)
    $row++
    $ws1.Range("A$row").Value = "TOTAL LOE (Days)"
    $ws1.Range("A$row").Font.Bold = $true
    $ws1.Range("A$row").Font.Size = 12
    $ws1.Range("B$row").Value = $totalLoe
    $ws1.Range("B$row").Font.Bold = $true
    $ws1.Range("B$row").Font.Size = 12

    # Auto-fit columns
    $ws1.Columns("A:B").AutoFit() | Out-Null

    # Worksheet 2: Phase Details
    $ws2 = $workbook.Sheets.Add([System.Reflection.Missing]::Value, $ws1)
    $ws2.Name = "Phase Details"
    $row = 1
    $ws2.Range("A$row").Value = "Phase"
    $ws2.Range("B$row").Value = "Description"
    $ws2.Range("C$row").Value = "Days"
    $ws2.Range("A$row:C$row").Font.Bold = $true
    $row++

    foreach ($phase in $phaseData) {
        $ws2.Range("A$row").Value = $phase.Phase
        $ws2.Range("B$row").Value = $phase.Description
        $ws2.Range("C$row").Value = $phase.Days
        $row++

        foreach ($task in $phase.Tasks) {
            $ws2.Range("A$row").Value = "  ↳ " + $task.Task
            $ws2.Range("B$row").Value = $task.Notes
            $ws2.Range("C$row").Value = $task.Days
            $row++
        }
    }

    $ws2.Columns("A:C").AutoFit() | Out-Null

    # Worksheet 3: Wave Schedule
    $ws3 = $workbook.Sheets.Add([System.Reflection.Missing]::Value, $ws2)
    $ws3.Name = "Wave Schedule"
    $row = 1
    $ws3.Range("A$row").Value = "Wave"
    $ws3.Range("B$row").Value = "Object Type"
    $ws3.Range("C$row").Value = "Quantity"
    $ws3.Range("D$row").Value = "Estimated Days"
    $ws3.Range("A$row:D$row").Font.Bold = $true
    $row++

    for ($w = 1; $w -le $userWaves; $w++) {
        $qty = if ($w -eq $userWaves) { $usersTotal - (($w - 1) * $config.waveDefaults.usersPerWave) } else { $config.waveDefaults.usersPerWave }
        $ws3.Range("A$row").Value = "Wave $w"
        $ws3.Range("B$row").Value = "Users"
        $ws3.Range("C$row").Value = $qty
        $ws3.Range("D$row").Value = $config.waveDefaults.daysPerUserWave
        $row++
    }

    for ($w = 1; $w -le $computerWaves; $w++) {
        $qty = if ($w -eq $computerWaves) { $computersTotal - (($w - 1) * $config.waveDefaults.computersPerWave) } else { $config.waveDefaults.computersPerWave }
        $ws3.Range("A$row").Value = "Wave $($userWaves + $w)"
        $ws3.Range("B$row").Value = "Computers"
        $ws3.Range("C$row").Value = $qty
        $ws3.Range("D$row").Value = $config.waveDefaults.daysPerComputerWave
        $row++
    }

    $ws3.Columns("A:D").AutoFit() | Out-Null

    # Worksheet 4: Complexity Drivers
    $ws4 = $workbook.Sheets.Add([System.Reflection.Missing]::Value, $ws3)
    $ws4.Name = "Complexity Drivers"
    $row = 1
    $ws4.Range("A$row").Value = "Driver"
    $ws4.Range("B$row").Value = "Count"
    $ws4.Range("C$row").Value = "Impact"
    $ws4.Range("A$row:C$row").Font.Bold = $true
    $row++

    $drivers = @(
        @{ Name = "Groups with Deep Nesting (≥3)"; Count = $groupsWithDeepNesting; Impact = "Increases remediation complexity" }
        @{ Name = "Domains with Deep OU Structure (≥6)"; Count = $ouWithDeepStructure; Impact = "Increases structure planning" }
        @{ Name = "Cross-Domain Groups"; Count = @($crossDomain).Count; Impact = "Requires special handling during waves" }
        @{ Name = "Duplicate SPNs"; Count = @($dupSpns).Count; Impact = "Needs cleanup before cutover" }
        @{ Name = "Empty Groups"; Count = @($emptyGroups).Count; Impact = "Cleanup opportunity" }
        @{ Name = "AdminSDHolder Protected"; Count = @($adminSd).Count; Impact = "Requires careful handling" }
        @{ Name = "Duplicate Objects (ADMT)"; Count = @($duplicateObjects).Count; Impact = "Conflict resolution required" }
        @{ Name = "Stale Accounts %"; Count = "$stalePct%"; Impact = "Cleanup candidate" }
    )

    foreach ($driver in $drivers) {
        $ws4.Range("A$row").Value = $driver.Name
        $ws4.Range("B$row").Value = $driver.Count
        $ws4.Range("C$row").Value = $driver.Impact
        $row++
    }

    $ws4.Columns("A:C").AutoFit() | Out-Null

    # Save
    $workbook.SaveAs($OutputPath)
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

    [pscustomobject]@{
        ExcelPath      = $OutputPath
        TotalLOE       = $totalLoe
        UserWaves      = $userWaves
        ComputerWaves  = $computerWaves
        RiskMultiplier = [math]::Round($riskMultiplier, 2)
    }
}
