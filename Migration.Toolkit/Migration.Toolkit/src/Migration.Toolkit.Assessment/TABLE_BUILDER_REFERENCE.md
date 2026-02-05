# Migration.Toolkit.Assessment Module - Table Builder Reference

## Overview
The `Migration.Toolkit.Assessment` module provides a comprehensive library of Word table builder functions for generating AD, Entra, and M365 assessment reports. All functions follow consistent patterns and integrate seamlessly with JSON-driven configuration.

## Module Structure

```
src/Migration.Toolkit.Assessment/
├── Migration.Toolkit.Assessment.psd1    # Module manifest (17 exported functions)
├── Migration.Toolkit.Assessment.psm1    # Module loader (dot-sources Private/Public)
├── Private/
│   └── Word-Helpers.ps1                 # COM object helpers (5 functions)
└── Public/
    ├── Invoke-AdAssessment.ps1          # Main orchestration function
    ├── Add-AdSimpleSummaryTable.ps1     # Metric/value pairs
    ├── Add-AdRawTableFromCsv.ps1        # Direct CSV rendering
    ├── Add-AdPivotTableFromCsv.ps1      # Group-by aggregation
    ├── Add-AdSingleRowSummaryFromCsv.ps1 # First row as metrics
    ├── Add-AdCountRowsSummary.ps1       # Simple row count
    ├── Add-AdUserStatsSummary.ps1       # AD user analysis
    ├── Add-AdDeviceSummary.ps1          # Workstations + servers
    ├── Add-AdOuStructureSummary.ps1     # OU depth analysis
    ├── Add-AdDomainDiscoveryTable.ps1   # Domain/forest metadata
    ├── Add-AdEntraUserSummary.ps1       # Entra ID user metrics
    ├── Add-AdEntraGuestDomainSummary.ps1 # Guest users by domain
    ├── Add-AdM365GroupSummary.ps1       # M365 groups + storage
    ├── Add-AdMailboxSummary.ps1         # Exchange mailboxes + Top 10
    ├── Add-AdOneDriveSummary.ps1        # OneDrive sites + Top 10
    ├── Add-AdTeamsActivitySummary.ps1   # Teams activity + Top 10
    └── Add-AdSharePointSummary.ps1      # SharePoint sites + Top 10
```

## Exported Functions (17 Total)

### Main Orchestration (1)
- **Invoke-AdAssessment**: Reads JSON config, opens Word template, processes sections with bookmark-based table insertion

### Base Table Builders (5)
- **Add-AdSimpleSummaryTable**: Metric/value pairs (ordered hashtable input)
- **Add-AdRawTableFromCsv**: Direct CSV to table with optional column filtering/renaming
- **Add-AdPivotTableFromCsv**: Group-by columns with Count/DistinctCount/Sum aggregation
- **Add-AdSingleRowSummaryFromCsv**: Extract first CSV row as metric/value pairs
- **Add-AdCountRowsSummary**: Simple row count with custom metric label

### AD-Specific Tables (4)
- **Add-AdUserStatsSummary**: Total, Enabled, Disabled, Stale, PwdNeverExpires (flexible column detection)
- **Add-AdDeviceSummary**: Combined servers + workstations with activity windows and legacy OS detection
- **Add-AdOuStructureSummary**: Primary summary (depth, leaf OUs) + secondary depth distribution table
- **Add-AdDomainDiscoveryTable**: Domain/forest metadata with FSMO roles

### Entra-Specific Tables (2)
- **Add-AdEntraUserSummary**: Member/guest counts, hybrid-synced vs cloud-only, stale sign-ins
- **Add-AdEntraGuestDomainSummary**: Guest accounts grouped by email domain with counts

### M365-Specific Tables (4)
- **Add-AdM365GroupSummary**: Active/inactive groups, Exchange + SharePoint storage aggregation
- **Add-AdMailboxSummary**: Primary summary (14 metrics) + "Top 10 Largest Mailboxes" table
- **Add-AdOneDriveSummary**: Storage metrics + "Top 10 Largest OneDrive Sites" table
- **Add-AdTeamsActivitySummary**: Teams activity + "Top 10 Most Active Teams" table
- **Add-AdSharePointSummary**: Site metrics + "Top 10 Largest SharePoint Sites" table

### Utility Functions (1)
- Located in **Private/Word-Helpers.ps1**:
  - `New-AdWordInstance`: Creates Word COM object
  - `Get-AdWordTableStyle`: Safe table style retrieval
  - `Get-AdBookmarkRange`: Bookmark-based range retrieval
  - `Set-AdHeaderFontColor`: Applies color to header row (hex or OLE)
  - `Remove-AdComObject`: COM cleanup helper

## Function Patterns

### Standard Parameters
All table builder functions accept:
- **Document** (mandatory): Word document COM object
- **Title** (mandatory): Caption/title for the table
- **CsvPath** (mandatory): Path to CSV data file
- **TableStyleName** (optional): Word table style name
- **InsertRange** (optional): Word range for bookmark-based insertion
- **HeaderFontColor** (optional): Hex string (#003087) or OLE color integer

### Return Value
All builders return `Microsoft.Office.Interop.Word.Range` pointing to the position immediately after the inserted table, enabling sequential table insertion.

### Common Patterns

#### Metric/Value Tables
Functions like `Add-AdSimpleSummaryTable`, `Add-AdUserStatsSummary` use ordered hashtables:
```powershell
$metrics = [ordered]@{
  "Total Users" = 1234
  "Enabled" = 980
  "Disabled" = 254
}
Add-AdSimpleSummaryTable -Document $doc -Title "User Summary" `
  -Metrics $metrics -TableStyleName "Grid Table 4 - Accent 1"
```

#### Multi-Table Builders
Functions like `Add-AdMailboxSummary`, `Add-AdOneDriveSummary` create:
1. **Primary summary table** (metric/value format)
2. **Secondary detail table** (Top 10 largest/most active)

Both tables use the same style and header color settings.

#### Activity Thresholds
M365 functions accept `-ActivityDays` parameter (default 90):
```powershell
Add-AdTeamsActivitySummary -Document $doc -Title "Teams Activity" `
  -CsvPath "Teams.csv" -ActivityDays 60
```

## Helper Functions (Internal)

### Date Parsing
```powershell
function Get-SafeDate($value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  try { return [datetime]$value } catch { return $null }
}
```

### Column Summing
```powershell
function Sum-ColumnAsInt64($data, $columnName) {
  $total = 0
  foreach ($row in $data) {
    $val = $row.$columnName
    if ($null -ne $val -and $val -ne '') {
      try { $total += [int64]$val } catch { }
    }
  }
  return $total
}
```

### Byte Formatting
```powershell
function Format-BytesHumanReadable([int64]$bytes) {
  if ($bytes -ge 1TB) { return "{0:N2} TB" -f ($bytes / 1TB) }
  if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
  if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
  if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
  return "$bytes bytes"
}
```

### Truthy Parsing
```powershell
function Get-IsTruthy($value) {
  if ($null -eq $value -or $value -eq '') { return $false }
  if ($value -is [bool]) { return $value }
  $str = $value.ToString().Trim().ToLower()
  return ($str -eq 'true' -or $str -eq '1' -or $str -eq 'yes')
}
```

## Expected CSV Column Names

### AD Users
- **Enabled** or **AccountEnabled**: Boolean/truthy value
- **LastLogonDate** or **LastLogon**: DateTime string
- **PasswordNeverExpires**: Boolean/truthy value
- **SamAccountName**, **UserPrincipalName**, **DisplayName**: Identifiers

### AD Devices (Computers)
- **OperatingSystem**: String (for legacy detection)
- **LastLogonDate** or **LastLogon**: DateTime string
- **Enabled** or **AccountEnabled**: Boolean/truthy value
- **Name**, **DNSHostName**: Identifiers

### Entra Users
- **UserType**: "Member" or "Guest"
- **OnPremisesSyncEnabled**: Boolean (hybrid detection)
- **SignInActivity.LastSignInDateTime**: DateTime string
- **CreatedDateTime**: DateTime string
- **UserPrincipalName**, **DisplayName**, **Mail**: Identifiers

### M365 Groups
- **LastActivityDate**: DateTime string
- **ExchangeStorageUsed**, **SharePointStorageUsed**: Int64 (bytes)
- **DisplayName**, **GroupType**: Identifiers

### Exchange Mailboxes
- **RecipientType** or **RecipientTypeDetails**: String (User/Shared/Archive)
- **HasArchive** or **ArchiveStatus**: Boolean/truthy
- **TotalItemSize** or **StorageUsedBytes**: Int64
- **ItemCount**: Int64
- **LastActivityDate** or **LastUserActionTime**: DateTime
- **DisplayName**, **UserPrincipalName**: Identifiers

### OneDrive Sites
- **Owner** or **OwnerPrincipalName**: String
- **StorageUsedGB**, **StorageQuotaGB**: Numeric
- **FileCount**: Int64
- **LastActivityDate**: DateTime

### Teams
- **TeamName** or **DisplayName**: String
- **ChannelCount**, **PostCount**, **MemberCount**: Int64
- **LastActivityDate**: DateTime

### SharePoint Sites
- **SiteUrl** or **Url**: String
- **StorageUsedGB**, **StorageQuotaGB**: Numeric
- **FileCount**: Int64
- **LastActivityDate**: DateTime

## Usage Examples

### Basic Table Builder
```powershell
Import-Module Migration.Toolkit.Assessment

$word = New-AdWordInstance
$doc = $word.Documents.Add()

# Simple summary table
$metrics = [ordered]@{
  "Total Domains" = 3
  "Forest Functional Level" = "Windows2016Forest"
  "Total Sites" = 5
}
Add-AdSimpleSummaryTable -Document $doc -Title "Forest Summary" `
  -Metrics $metrics -TableStyleName "Grid Table 4 - Accent 1" `
  -HeaderFontColor "#003087"

# AD user stats from CSV
Add-AdUserStatsSummary -Document $doc -Title "Active Directory Users" `
  -CsvPath "C:\data\AD_Users.csv" -TableStyleName "Grid Table 4 - Accent 1" `
  -StaleDays 90
```

### Sequential Table Insertion
```powershell
$range = $doc.Content
$range.Collapse([Microsoft.Office.Interop.Word.WdCollapseDirection]::wdCollapseEnd)

$range = Add-AdUserStatsSummary -Document $doc -Title "AD Users" `
  -CsvPath "Users.csv" -InsertRange $range

$range = Add-AdDeviceSummary -Document $doc -Title "Devices" `
  -CsvPath "Computers.csv" -WorkstationCsv "Workstations.csv" `
  -InsertRange $range

$range = Add-AdOuStructureSummary -Document $doc -Title "OU Structure" `
  -CsvPath "OUs.csv" -InsertRange $range
```

### Bookmark-Based Insertion
```powershell
$template = $word.Documents.Open("C:\templates\Assessment.docx")

# Insert at specific bookmarks
$range1 = Get-AdBookmarkRange -Document $template -BookmarkName "ADUsers"
Add-AdUserStatsSummary -Document $template -Title "User Summary" `
  -CsvPath "Users.csv" -InsertRange $range1

$range2 = Get-AdBookmarkRange -Document $template -BookmarkName "EntraUsers"
Add-AdEntraUserSummary -Document $template -Title "Entra ID Users" `
  -CsvPath "EntraUsers.csv" -InsertRange $range2

$template.SaveAs("C:\output\Assessment_Report.docx")
```

### JSON-Driven Orchestration (Future)
```powershell
# This is the intended workflow after JSON schema is defined
Invoke-AdAssessment -ConfigPath "C:\config\Assessment_Config.json"
```

## Next Steps

### Immediate Tasks
1. **Define JSON configuration schema** for `Invoke-AdAssessment`
2. **Update Invoke-AdAssessment** to route TableType to appropriate builder functions
3. **Create sample JSON configs** for common assessment scenarios
4. **Build Word templates** with bookmarks for section insertion

### JSON Schema (Proposed)
```json
{
  "TemplatePath": "C:\\templates\\Assessment.docx",
  "OutputRoot": "C:\\output",
  "Customer": "Contoso",
  "Placeholders": {
    "{{CustomerName}}": "Contoso Corporation",
    "{{AssessmentDate}}": "2026-01-28"
  },
  "Sections": [
    {
      "Bookmark": "ADUsers",
      "Title": "Active Directory User Summary",
      "TableType": "AdUserStats",
      "CsvPath": "C:\\data\\AD_Users.csv",
      "TableStyleName": "Grid Table 4 - Accent 1",
      "HeaderFontColor": "#003087",
      "Options": {
        "StaleDays": 90
      }
    },
    {
      "Bookmark": "Mailboxes",
      "Title": "Exchange Online Mailboxes",
      "TableType": "Mailbox",
      "CsvPath": "C:\\data\\Mailboxes.csv",
      "TableStyleName": "Grid Table 4 - Accent 1",
      "HeaderFontColor": "#003087"
    }
  ]
}
```

### TableType Enumeration
Map JSON `TableType` values to function names:
- `SimpleSummary` → `Add-AdSimpleSummaryTable`
- `RawTable` → `Add-AdRawTableFromCsv`
- `PivotTable` → `Add-AdPivotTableFromCsv`
- `SingleRowSummary` → `Add-AdSingleRowSummaryFromCsv`
- `CountRows` → `Add-AdCountRowsSummary`
- `AdUserStats` → `Add-AdUserStatsSummary`
- `AdDevices` → `Add-AdDeviceSummary`
- `AdOuStructure` → `Add-AdOuStructureSummary`
- `AdDomainDiscovery` → `Add-AdDomainDiscoveryTable`
- `EntraUsers` → `Add-AdEntraUserSummary`
- `EntraGuestDomains` → `Add-AdEntraGuestDomainSummary`
- `M365Groups` → `Add-AdM365GroupSummary`
- `Mailboxes` → `Add-AdMailboxSummary`
- `OneDrive` → `Add-AdOneDriveSummary`
- `TeamsActivity` → `Add-AdTeamsActivitySummary`
- `SharePoint` → `Add-AdSharePointSummary`

### Testing Strategy
1. **Unit tests**: Test each table builder with sample CSV data
2. **Integration tests**: Test `Invoke-AdAssessment` with full JSON configs
3. **Template tests**: Validate bookmark insertion with real Word templates
4. **Edge cases**: Empty CSVs, missing columns, invalid data types

### Documentation
- Create **README.md** with quickstart guide
- Add **EXAMPLES.md** with common scenarios
- Document **JSON schema** with all options
- Create **TROUBLESHOOTING.md** for common issues

## Benefits Over Previous Scripts

### Before (Scattered Scripts)
- Mixed analysis and rendering logic
- Hard-coded table structures
- Manual template population
- Difficult to maintain and extend

### After (Module-Based)
- ✅ Modular table builders (reusable across assessments)
- ✅ JSON-driven configuration (no code changes for new reports)
- ✅ Consistent patterns (all functions follow same structure)
- ✅ Testable components (unit test each builder separately)
- ✅ Extensible (add new table types without breaking existing ones)
- ✅ Version controlled (module versioning in manifest)
- ✅ Import once, use everywhere (`Import-Module Migration.Toolkit.Assessment`)

## Module Metadata

- **Version**: 0.1.0
- **GUID**: 9bb6a36b-4f19-4f1a-8ff1-6d1e2a9b1ed6
- **PowerShell Version**: 5.1+
- **Tags**: ActiveDirectory, Entra, M365, Assessment, Word, Reporting
- **Dependencies**: Word.Application COM object, Migration.Toolkit (for CSV data)

## Installation

```powershell
# From repository root
Import-Module "$PWD\src\Migration.Toolkit.Assessment" -Force

# Verify exports
Get-Command -Module Migration.Toolkit.Assessment | Select-Object Name
```

## Quick Reference

### Import Module
```powershell
Import-Module Migration.Toolkit.Assessment
```

### Create Word Instance
```powershell
$word = New-AdWordInstance
$doc = $word.Documents.Add()
```

### Insert Table
```powershell
$range = Add-AdUserStatsSummary -Document $doc -Title "Users" `
  -CsvPath "Users.csv" -TableStyleName "Grid Table 4 - Accent 1"
```

### Save Document
```powershell
$doc.SaveAs("C:\output\Report.docx")
$word.Quit()
Remove-AdComObject $word
```
