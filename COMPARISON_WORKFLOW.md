# Migration Comparison Workflow Guide

## Overview

The full-path implementation includes environment tagging, automated comparison reports, and readiness validation for source→target AD migrations.

## Architecture

### Output Structure

```
Reports/
├── ADOnly_<timestamp>/              # Source discovery run
│   ├── 10_forest/
│   ├── 20_domains/
│   ├── 90_logs/
│   ├── LC__Assessment__Report__Source.html
│   ├── LC__Migration__Planning__Report.html
│   └── LC__Migration__LOE__<Customer>__Source.xlsx
│
├── ADOnly__target_<timestamp>/      # Target discovery run
│   ├── 10_forest/
│   ├── 20_domains/
│   ├── 90_logs/
│   └── LC__Assessment__Report__Target.html
│
├── LC__Comparison__Report__<timestamp>.html
└── LC__Migration__Readiness__Checklist__<timestamp>.html
```

## Quick Start

### Option 1: Automated Full Workflow (Recommended)

Run the orchestrator script to automatically execute discovery in both environments and generate all reports:

```powershell
# Import module
Import-Module "$PWD\src\Lagana.Consulting.Toolkit" -Force

# Run complete workflow
$result = Invoke-LcDiscoveryComparison -CustomerName "Contoso Corp" -OpenReports

# View results
$result | Format-Table
```

**What happens automatically:**
1. Runs source discovery (tags as "Source")
2. Runs target discovery (tags as "Target")
3. Generates side-by-side metrics comparison HTML
4. Generates migration readiness validation checklist
5. Generates assessment reports for both environments
6. Generates migration planning report
7. Generates LOE estimation Excel workbook
8. Opens reports in default browser/viewer

**Output time:** ~15-20 minutes (depending on forest size)

### Option 2: Manual Step-by-Step

For more control or to run environments at different times:

#### Step 1: Run Discovery on Source

```powershell
# Option A: Use discovery script directly
& "c:\scripts\AD_Discovery_ADOnly_LC.ps1" `
  -Environment "Source" `
  -OutputRoot "C:\Reports" `
  -Prefix "ADOnly" `
  -CustomerName "Contoso Corp"

# Option B: Use discovery script with specific DC
& "c:\scripts\AD_Discovery_ADOnly_LC.ps1" `
  -Environment "Source" `
  -OutputRoot "C:\Reports" `
  -SourceServer "dc1.source.com" `
  -CustomerName "Contoso Corp"
```

**Output:** `C:\Reports\ADOnly_<timestamp>/`

#### Step 2: Run Discovery on Target

```powershell
& "c:\scripts\AD_Discovery_ADOnly_LC.ps1" `
  -Environment "Target" `
  -OutputRoot "C:\Reports" `
  -Prefix "ADOnly" `
  -CustomerName "Contoso Corp"
```

**Output:** `C:\Reports\ADOnly__target_<timestamp>/`

#### Step 3: Generate Comparison Reports

```powershell
# Find the latest source and target runs
$sourceRunRoot = Get-ChildItem "C:\Reports" -Directory |
  Where-Object { $_.Name -match '^ADOnly_' } |
  Sort-Object CreationTime -Desc | Select-Object -First 1 -ExpandProperty FullName

$targetRunRoot = Get-ChildItem "C:\Reports" -Directory |
  Where-Object { $_.Name -match '^ADOnly__target_' } |
  Sort-Object CreationTime -Desc | Select-Object -First 1 -ExpandProperty FullName

# Generate comparison report
$comparison = New-LcEnvironmentComparisonReport `
  -SourceRunRoot $sourceRunRoot `
  -TargetRunRoot $targetRunRoot `
  -CustomerName "Contoso Corp"

# View comparison
Invoke-Item $comparison.ReportPath
```

#### Step 4: Generate Readiness Checklist

```powershell
# Generate readiness checklist
$readiness = New-LcMigrationReadinessChecklist `
  -SourceRunRoot $sourceRunRoot `
  -TargetRunRoot $targetRunRoot `
  -CustomerName "Contoso Corp"

# View checklist
Invoke-Item $readiness.ChecklistPath
```

## Key Features

### Environment Tagging

The discovery script now accepts an `-Environment` parameter (default: "Source"):

```powershell
# Discovery outputs automatically include environment info
# Source run creates: ADOnly_<timestamp>/
# Target run creates: ADOnly__target_<timestamp>/

# Environment info stored in: <RunRoot>/99_manifest/LC__Run__Info__Run.csv
# Can retrieve with:
Import-Csv "C:\Reports\ADOnly_<timestamp>\99_manifest\LC__Run__Info__Run.csv"
```

### Comparison Report

The comparison report (`New-LcEnvironmentComparisonReport`) generates HTML with:

- **Forest-Level Metrics:** Side-by-side comparison of users, groups, computers, trusts
- **Domain-Level Breakdown:** Per-domain delta analysis
- **New Objects in Target:** Identifies new domains or unexpected objects
- **Missing Objects:** Identifies domains or objects in source not migrated
- **Professional Styling:** Embedded CSS for easy distribution

### Readiness Checklist

The readiness checklist (`New-LcMigrationReadinessChecklist`) provides:

- **Automatic Validation:** Tests that count objects match expectations (Pass/Fail)
- **Manual Review Items:** Tasks requiring human verification (7 categories)
- **Pre-Cutover Validation:** Network, application, GPO, permissions checks
- **Rollback Preparation:** Documents rollback procedures
- **Print-Friendly:** Styled for both screen and print output

**Checklist categories:**
1. Object Reconciliation
2. Domain Configuration
3. Special Objects & Privileges
4. Risk Mitigation
5. Network & Replication
6. Application Readiness
7. Cutover Preparation

### Orchestrator Script

The orchestrator (`Invoke-LcDiscoveryComparison`) automates the entire workflow:

```powershell
Invoke-LcDiscoveryComparison `
  -SourceServer "dc1.source.com" `     # Optional: specific DC in source
  -TargetServer "dc1.target.com" `     # Optional: specific DC in target
  -OutputRoot "C:\Reports" `           # Where to store outputs
  -CustomerName "Contoso Corp" `       # For report headers
  -GenerateReports `                   # Auto-generate all reports
  -OpenReports                         # Auto-open reports in viewer
```

Returns object with paths to all generated reports:
```
SourceRunRoot        : C:\Reports\ADOnly_<timestamp>
TargetRunRoot        : C:\Reports\ADOnly__target_<timestamp>
ComparisonReport     : C:\Reports\ADOnly_<timestamp>\LC__Comparison__Report__<timestamp>.html
ReadinessChecklist   : C:\Reports\ADOnly_<timestamp>\LC__Migration__Readiness__Checklist__<timestamp>.html
SourceAssessment     : C:\Reports\ADOnly_<timestamp>\LC__Assessment__Report__Source.html
TargetAssessment     : C:\Reports\ADOnly__target_<timestamp>\LC__Assessment__Report__Target.html
PlanningReport       : C:\Reports\ADOnly_<timestamp>\LC__Migration__Planning__Report.html
LoeExcel             : C:\Reports\ADOnly_<timestamp>\LC__Migration__LOE__<Customer>__Source.xlsx
```

## Report Descriptions

### Assessment Report (Per Environment)

Analyzes single environment for:
- Identity metrics (users, groups, computers, contacts)
- Infrastructure health (DCs, replication, FSMO roles)
- Security posture (stale accounts, weak policies, privileged access)
- Complexity drivers (group nesting, OU depth, SPN overload)
- Risk summary with remediation recommendations

### Migration Planning Report (Source)

Combines all assessments for:
- Complexity score (0-100) weighted by forest/domain characteristics
- Phase-by-phase LOE estimates (Assessment, Remediation, Execution, Post-migration)
- Wave-based migration schedule for users and computers
- SOW outline with key deliverables

### LOE Excel Workbook (Source)

Multi-sheet workbook for:
- **Executive Summary:** Total effort, phase breakdown, risk factors
- **Phase Details:** Task-by-task breakdown with multipliers and estimates
- **Wave Schedule:** User/computer migration waves with quantities and days
- **Complexity Drivers:** List of identified risk factors with counts and impact

Includes customizable configuration via `config/LOE.config.json` for:
- Task definitions and base days
- Volume multipliers (users per wave, computers per day)
- Risk multipliers (nesting depth, OU depth, cross-domain, stale accounts)

### Comparison Report

Side-by-side analysis showing:
- Domain count, user count, group count, computer count deltas
- New domains detected in target (if any)
- Missing domains from target (if any)
- Per-domain user/group/computer reconciliation
- Color-coded highlights for matching, over-migrated, under-migrated objects

### Readiness Checklist

Pre-cutover validation with:
- Object reconciliation tests (automatic Pass/Fail)
- Domain configuration verification (manual)
- Special object migration (service accounts, privileged groups)
- Risk remediation validation
- Network and replication readiness
- Application compatibility testing
- Cutover preparation and rollback planning

## Troubleshooting

### Issue: "Discovery script not found"

**Fix:** Update the path in orchestrator or copy discovery script:
```powershell
Copy-Item "c:\scripts\AD_Discovery_ADOnly_LC.ps1" -Destination "c:\scripts\"
```

### Issue: "Source/Target run root not found"

**Cause:** Discovery failed silently or output folder name mismatch

**Fix:** Check discovery output manually:
```powershell
Get-ChildItem "C:\Reports" -Directory | Where-Object { $_.Name -match 'ADOnly' }
```

### Issue: "Failed to import CSV"

**Cause:** CSV file doesn't exist or is malformed

**Fix:** Verify discovery completed successfully:
```powershell
Get-ChildItem "C:\Reports\ADOnly_<timestamp>" -Recurse -Filter *.csv | Measure-Object
```

## Advanced Usage

### Custom Discovery Paths

```powershell
# Run discovery with specific target forests
& "AD_Discovery_ADOnly_LC.ps1" `
  -Environment "Source" `
  -OutputRoot "\\fileserver\reports" `
  -SourceServer "gc1.source.com" `
  -CustomerName "Large Migration"
```

### Generate Reports from Existing Outputs

```powershell
# Don't re-run discovery, just regenerate reports
$source = "C:\Reports\ADOnly_20260121-132028"
$target = "C:\Reports\ADOnly__target_20260121-143515"

# Comparison
New-LcEnvironmentComparisonReport -SourceRunRoot $source -TargetRunRoot $target

# Readiness
New-LcMigrationReadinessChecklist -SourceRunRoot $source -TargetRunRoot $target

# Assessment for source
New-LcAssessmentReport -RunRoot $source

# Assessment for target
New-LcAssessmentReport -RunRoot $target
```

### Batch Multiple Migrations

```powershell
# Compare multiple source→target pairs
$migrations = @(
  @{ Name = "LAB→PROD"; Source = "C:\Reports\ADOnly_lab"; Target = "C:\Reports\ADOnly__target_prod" }
  @{ Name = "DEV→STAGING"; Source = "C:\Reports\ADOnly_dev"; Target = "C:\Reports\ADOnly__target_staging" }
)

foreach ($mig in $migrations) {
  Write-Host "Processing: $($mig.Name)"

  New-LcEnvironmentComparisonReport `
    -SourceRunRoot $mig.Source `
    -TargetRunRoot $mig.Target `
    -CustomerName $mig.Name
}
```

## Next Steps After Generating Reports

1. **Review Comparison Report:** Identify domain/object count deltas
2. **Execute Readiness Checklist:** Get sign-offs on manual verification items
3. **Address Failures:** Any "Fail" items in checklist must be resolved
4. **Plan Waves:** Use LOE workbook to schedule user/computer migration
5. **Dry-Run Cutover:** Execute migration process in lab using topology
6. **Validate Applications:** Test key apps with sample of users
7. **Prepare Rollback:** Document rollback procedures for each phase
8. **Execute Cutover:** Run migration following wave schedule
9. **Monitor:** Watch replication, logon issues, application problems
10. **Validate:** Run readiness checklist again post-cutover to confirm success

## Support

For detailed function documentation, use:

```powershell
Get-Help New-LcEnvironmentComparisonReport -Detailed
Get-Help New-LcMigrationReadinessChecklist -Detailed
Get-Help Invoke-LcDiscoveryComparison -Detailed
```

## File Locations

- **Discovery Script:** `client-scripts/src/client.scripts/Public/AD_Discovery_ADOnly_LC.ps1`
- **Toolkit Module:** `lc-toolkit/src/Lagana.Consulting.Toolkit/`
- **LOE Config:** `lc-toolkit/config/LOE.config.json`
- **Report Functions:**
  - `New-LcEnvironmentComparisonReport.ps1`
  - `New-LcMigrationReadinessChecklist.ps1`
  - `Invoke-LcDiscoveryComparison.ps1`
  - `New-LcAssessmentReport.ps1`
  - `New-LcMigrationPlanningReport.ps1`
  - `New-LcMigrationLoeExcel.ps1`
