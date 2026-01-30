# Test script to verify section generation fixes
param(
    [string]$DiscoveryPath = ".\compare\ADOnly_20260121-132028"
)

Write-Host "=== Testing Fixed Sections ===" -ForegroundColor Cyan
Write-Host "Discovery Path: $DiscoveryPath" -ForegroundColor Yellow

# Import the module
$modulePath = ".\src\Migration.Toolkit"
if (-not (Test-Path $modulePath)) {
    Write-Error "Module path not found: $modulePath"
    exit 1
}

Import-Module $modulePath -Force

# Test data
$config = @{
    DiscoveryOutputPath = $DiscoveryPath
    OutputPath          = ".\output\test-assessment"
    Styling             = @{
        TableStyleName = "BT-Default"
    }
}

# Ensure output directory
if (-not (Test-Path $config.OutputPath)) {
    New-Item -ItemType Directory -Path $config.OutputPath -Force | Out-Null
}

Write-Host "`nTesting sections..." -ForegroundColor Yellow

# Test 1: Groups Summary (Count parameter fix)
Write-Host "`n1. Groups Summary" -ForegroundColor Cyan
$groupsCsvPath = Join-Path $DiscoveryPath "20_domains\Domain_*\AD_Groups_Detailed.csv" -Resolve | Select-Object -First 1
if ($groupsCsvPath) {
    try {
        $groupsData = Import-Csv $groupsCsvPath
        $grouped = $groupsData | Group-Object Category | ForEach-Object {
            [pscustomobject]@{
                Category = $_.Name
                Count    = $_.Count
            }
        }
        Write-Host "   Groups data: $(($grouped | Measure-Object).Count) categories" -ForegroundColor Green
        Write-Host "   Sample row count: $($grouped[0].Count) (Type: $($grouped[0].Count.GetType().Name))" -ForegroundColor Green
    }
    catch {
        Write-Host "   ERROR: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "   No Groups CSV found" -ForegroundColor Yellow
}

# Test 2: OU Structure (Count property fix)
Write-Host "`n2. OU Structure" -ForegroundColor Cyan
$ouCsvPath = Join-Path $DiscoveryPath "20_domains\Domain_*\AD_OrganizationalUnits.csv" -Resolve | Select-Object -First 1
if ($ouCsvPath) {
    try {
        $ouData = Import-Csv $ouCsvPath
        $ouArray = @($ouData)
        Write-Host "   OU data: $($ouArray.Count) OUs found" -ForegroundColor Green

        # Test depth grouping (like in Add-AdOuStructureSummary)
        $depthGroups = $ouData | Group-Object Depth | Sort-Object Name
        $depthRows = foreach ($g in $depthGroups) {
            [pscustomobject]@{
                Level = $g.Name
                OUs   = $g.Count
            }
        }
        $depthArray = @($depthRows)
        Write-Host "   Depth distribution: $($depthArray.Count) depth levels" -ForegroundColor Green
    }
    catch {
        Write-Host "   ERROR: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "   No OU CSV found" -ForegroundColor Yellow
}

# Test 3: Device Summary (Keys property fix)
Write-Host "`n3. Device Summary" -ForegroundColor Cyan
$computersCsvPath = Join-Path $DiscoveryPath "20_domains\Domain_*\AD_Computers_Extended.csv" -Resolve | Select-Object -First 1
if ($computersCsvPath) {
    try {
        $computerData = Import-Csv $computersCsvPath

        # Test the metrics creation (like in Add-AdDeviceSummary)
        $serverMetrics = @{}
        $workstationMetrics = @{}

        foreach ($row in $computerData) {
            $osType = if ($row.OperatingSystem -like "*Server*") { "Server" } else { "Workstation" }
            if ($osType -eq "Server") {
                $serverMetrics[$row.OperatingSystem]++
            }
            else {
                $workstationMetrics[$row.OperatingSystem]++
            }
        }

        if ($serverMetrics.Count -gt 0) {
            Write-Host "   Server metrics created: $($serverMetrics.Count) OS types" -ForegroundColor Green
            Write-Host "   Server metrics has Keys: $($serverMetrics.Keys -ne $null)" -ForegroundColor Green
        }
        if ($workstationMetrics.Count -gt 0) {
            Write-Host "   Workstation metrics created: $($workstationMetrics.Count) OS types" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "   ERROR: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "   No Computers CSV found" -ForegroundColor Yellow
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
