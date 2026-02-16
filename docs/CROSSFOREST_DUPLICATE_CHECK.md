# Cross-Forest Duplicate Check Function

## Overview
`Invoke-AdCrossForestDuplicateCheck` is a dedicated function for analyzing cross-forest duplicate objects in AD migration scenarios. It extracts and focuses solely on the duplicate checking logic from `Invoke-AdDiscoveryAnalysis`.

## Features
- ✅ Analyzes source and target AD environments for duplicate conflicts
- ✅ Detects duplicate sAMAccountNames, UPNs, and mail attributes across forests
- ✅ Supports JSON configuration file or individual parameters
- ✅ Generates CSV reports or returns objects for further processing
- ✅ Filters results to show only cross-forest conflicts (not within-domain duplicates)
- ✅ Includes conflict summaries (user/group/computer breakdown)

## Usage

### 1. Using Default Config File
Uses the built-in config file at:
`C:\Users\PLagana\OneDrive - Quest\Documents\GitHub\Migration.Toolkit\src\Migration.Toolkit.Analysis\config\Anlaysis_MultiSource_Config.json`

```powershell
Import-Module ".\src\Migration.Toolkit\Migration.Toolkit.psd1" -Force
Import-Module ".\src\Migration.Toolkit.Analysis\Migration.Toolkit.Analysis.psd1" -Force

# Run analysis with default config
Invoke-AdCrossForestDuplicateCheck
```

### 2. Using Parameters (Override Config)
```powershell
$result = Invoke-AdCrossForestDuplicateCheck `
  -SourceRunRoots 'C:\Reports\Source1', 'C:\Reports\Source2' `
  -TargetRunRoot 'C:\Reports\Target' `
  -OutputRoot 'C:\Reports\Analysis'

# View results
$result | Format-List
```

### 3. Get Objects for Further Processing
Use `-PassThru` to get duplicate objects instead of just a CSV report:
```powershell
$duplicates = Invoke-AdCrossForestDuplicateCheck -PassThru

# Filter high-severity conflicts
$critical = $duplicates | Where-Object { $_.Severity -eq 'High' }

# Export filtered results
$critical | Export-Csv "C:\Reports\HighRiskConflicts.csv" -NoTypeInformation
```

### 4. Custom Config File
```powershell
# Create custom config
$config = @{
    SourceRunRoots = @('C:\path\to\source1', 'C:\path\to\source2')
    TargetRunRoot  = 'C:\path\to\target'
    OutputRoot     = 'C:\path\to\output'
} | ConvertTo-Json | Out-File "C:\custom.config.json"

# Run with custom config
Invoke-AdCrossForestDuplicateCheck -ConfigPath "C:\custom.config.json"
```

## Output

### CSV Report
When not using `-PassThru`, generates:
- `AD__Duplicate__Objects__Cross_Forest.csv` in the OutputRoot directory

Contains columns:
- `ConflictType` - Type of conflict (SamAccountName, UserPrincipalName, Mail)
- `ConflictValue` - The actual conflicting value
- `ObjectClasses` - Types of objects involved (user, group, computer)
- `ConflictCount` - Number of objects with this conflict
- `ConflictingDomains` - Domains involved in the conflict
- `ConflictingDNs` - Distinguished names of conflicting objects

### Return Object (with `-PassThru`)
Returns a hashtable with:
```powershell
@{
    ReportPath      = "path\to\report.csv"
    ConflictCount   = <total conflicts>
    Conflicts       = @(PSCustomObject[])  # Array of conflict objects
    UserConflicts   = <count>
    GroupConflicts  = <count>
    CompConflicts   = <count>
}
```

## Configuration File Format (JSON)
```json
{
  "SourceRunRoots": [
    "C:\\scripts\\Reports\\ADOnly_20260122-103143",
    "C:\\scripts\\Reports\\ADOnly2_20260122-110000"
  ],
  "TargetRunRoot": "C:\\scripts\\Reports\\ADOnly__target_20260122-123933",
  "OutputRoot": "C:\\scripts\\Reports\\Analysis_MultiSourceTest",
  "CustomerName": "Lab Multi-Source Test"
}
```

**Note:** The function uses only `SourceRunRoots`, `TargetRunRoot`, and `OutputRoot`. Other fields are ignored.

## Parameter Precedence
1. **Command-line parameters** (highest priority) - override config file
2. **Config file values** - used if parameters not provided
3. **Defaults** - OutputRoot defaults to current directory with timestamp

## Expected Discovery Output Structure
```
DiscoveryRoot/
├── 10_forest/
│   └── AD__Forest__* .csv files
└── 20_domains/
    └── DomainName.com/
        ├── AD__Domain__Identity__Users__*.csv
        ├── AD__Domain__Identity__Groups__*.csv
        └── AD__Domain__Identity__ComputersAll__*.csv
```

## Examples

### Find All High-Risk User Conflicts
```powershell
$dups = Invoke-AdCrossForestDuplicateCheck -PassThru
$userConflicts = $dups | Where-Object {
    $_.ObjectClasses -match 'user' -and $_.Severity -eq 'High'
}
$userConflicts | Format-Table ConflictValue, ConflictingDomains, ConflictCount
```

### Generate Report and Check File
```powershell
$result = Invoke-AdCrossForestDuplicateCheck -OutputRoot 'C:\Reports\Latest'
if ($result.ConflictCount -gt 0) {
    Write-Host "Found $($result.ConflictCount) conflicts - see $($result.ReportPath)"
    Invoke-Item $result.ReportPath
} else {
    Write-Host "No cross-forest conflicts detected!"
}
```

### Analyze Multiple Source Forests
```powershell
$sources = @(
    'C:\Reports\SourceForest1_20260122',
    'C:\Reports\SourceForest2_20260122',
    'C:\Reports\SourceForest3_20260122'
)

$results = Invoke-AdCrossForestDuplicateCheck `
  -SourceRunRoots $sources `
  -TargetRunRoot 'C:\Reports\TargetForest_20260122' `
  -OutputRoot 'C:\Reports\ConsolidatedAnalysis'

Write-Host "Analysis complete:"
Write-Host "  User conflicts: $($results.UserConflicts)"
Write-Host "  Group conflicts: $($results.GroupConflicts)"
Write-Host "  Computer conflicts: $($results.CompConflicts)"
```

## Requirements
- PowerShell 7.0+ (analysis module requirement)
- Migration.Toolkit module loaded
- Migration.Toolkit.Analysis module loaded
- Valid discovery output directories with CSV data

## Troubleshooting

### Config file not found
- Function will work with parameters if config file doesn't exist
- Provide `-SourceRunRoots`, `-TargetRunRoot`, and `-OutputRoot` explicitly

### No duplicates found
- Check that discovery output contains data in expected subdirectories
- Verify CSV file naming conventions match the function's search patterns

### Access denied errors
- Ensure you have read permissions on source directories
- Verify write permissions on output directory

## Integration with Existing Workflows
This function can replace the duplicate-checking portion of `Invoke-AdDiscoveryAnalysis` when you only need duplicate analysis without full discovery orchestration.

Compare:
- **`Invoke-AdDiscoveryAnalysis`** - Full workflow: forest analysis, domain analysis, group membership, risk assessment, **and** cross-forest duplicates
- **`Invoke-AdCrossForestDuplicateCheck`** - Focused: **only** cross-forest duplicate analysis
