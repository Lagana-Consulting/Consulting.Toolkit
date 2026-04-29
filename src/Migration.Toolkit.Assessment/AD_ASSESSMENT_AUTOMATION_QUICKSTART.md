# AD Assessment Automation - Quick Start Guide

## What This Solves

**Before**: Manually select CSV files, call assessment functions, manage Word insertion
```powershell
# Manual way (tedious, error-prone)
$doc = $word.Documents.Open("template.docx")

# Forest summary
$forestCSV = Get-ChildItem "Discovery\10_forest\*Forest_Summary*.csv"
Add-AdForestSummary -Document $doc -CsvPath $forestCSV.FullName ...

# Domain trusts
$trustsCSV = Get-ChildItem "Discovery\10_forest\*Trusts*.csv"
Add-AdTrustInformation -Document $doc -CsvPath $trustsCSV.FullName ...

# Per-domain users
foreach ($domain in (Get-ChildItem "Discovery\20_domains\Domain-*")) {
    $userCSV = Get-ChildItem "$($domain.FullName)\*Users*.csv"
    Add-AdUserStatsSummary -Document $doc -CsvPath $userCSV.FullName ...
}
# ... many more repetitions ...
```

**After**: One function call
```powershell
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath "C:\Discovery\AD_forest__vts_20260129-120000" `
  -TemplatePath "C:\Templates\AD_Assessment.dotx" `
  -OutputPath "C:\Reports\Assessment.docx"
```

Or use the bundled module template:

```powershell
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath "C:\Discovery\AD_forest__vts_20260129-120000" `
  -UseBundledDiscoveryTemplate `
  -OutputPath "C:\Reports\Assessment.docx"
```

## How to Use

### Step 1: Place Template

Create or use an existing Word template at `C:\Templates\AD_Assessment.dotx`:
- Optional: Add bookmarks for sections (Forest_Summary, Domain_Users, etc.)
- Recommended: Apply preferred theme/styles
- Tables will be inserted sequentially or to bookmarks

### Step 2: Run Automation

```powershell
# Import module
Import-Module "C:\GitHub\Migration.Toolkit\src\Migration.Toolkit.Assessment" -Force

# Run automation
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath "C:\Discovery\AD_forest__vts_20260129-120000" `
  -TemplatePath "C:\Templates\AD_Assessment.dotx" `
  -OutputPath "C:\Reports\Assessment.docx"
```

### Step 3: Review Output

Open generated `Assessment.docx` and verify:
- All sections included (or only requested sections if filtered)
- Tables formatted correctly
- Data accurate

## Configuration: ADAssessmentMap.json

Located in: `src\Migration.Toolkit.Assessment\config\ADAssessmentMap.json`

### What It Contains

Maps Discovery output file patterns → Assessment table builders:

```json
{
  "Sections": [
    {
      "Id": "Forest_Summary",
      "Title": "Forest Summary",
      "Builder": "Add-AdForestSummary",
      "DataSource": {
        "Path": "10_forest",
        "Pattern": "*__Forest__Summary__Forest.csv"
      }
    },
    {
      "Id": "Domain_Users",
      "Title": "Users Summary",
      "Builder": "Add-AdUserStatsSummary",
      "DataSource": {
        "Path": "20_domains/{Domain}",
        "Pattern": "*__Identity__Users__Domain-*.csv",
        "PerDomain": true
      }
    }
    // ... more sections ...
  ]
}
```

### Customizing Sections

#### Include Only Specific Sections

```powershell
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath $path `
  -TemplatePath $template `
  -OutputPath $output `
  -Sections @("Forest_Summary", "Domain_Users", "Domain_Computers")
```

#### Customize Table Styling

```powershell
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath $path `
  -TemplatePath $template `
  -OutputPath $output `
  -TableStyleName "Light Grid Accent 1" `
  -HeaderFontColor "FF0000"
```

#### Add Custom Sections to Config

Edit `ADAssessmentMap.json` and add:

```json
{
  "Id": "Domain_CustomTable",
  "Title": "Custom Data Table",
  "Category": "PerDomain",
  "Builder": "Add-AdRawTableFromCsv",
  "DataSource": {
    "Path": "20_domains/{Domain}",
    "Pattern": "*__Custom__Data__Domain-*.csv",
    "PerDomain": true
  },
  "Columns": ["Col1", "Col2", "Col3"],
  "Mode": "Table"
}
```

Then use in automation:

```powershell
Invoke-ADAssessmentAutomation ... -Sections @("Forest_Summary", "Domain_CustomTable")
```

## Discovery Output Structure

Your discovery must produce this directory layout:

```
AD_forest__vts_<timestamp>/
├── 10_forest/
│   ├── LC__AD__Forest__Summary__Forest.csv
│   ├── LC__AD__Forest__Security__Trusts__Forest.csv
│   ├── LC__AD__Forest__Network__Sites__Forest.csv
│   ├── LC__AD__Forest__Network__Subnets__Forest.csv
│   └── LC__AD__Forest__Identity__UpnSuffixes__Forest.csv
├── 20_domains/
│   ├── Domain-sourcelab.com/
│   │   ├── LC__AD__Domain__Summary__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__Users__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__ComputersServers__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__ComputersWorkstations__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__Groups__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Security__PasswordPolicyDefault__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__GPO__Inventory__Domain-sourcelab.com.csv
│   │   └── LC__AD__Domain__Structure__OrganizationalUnits__Domain-sourcelab.com.csv
│   └── Domain-child.sourcelab.com/
│       └── (same structure per domain)
└── 00_schemas/
    └── (metadata - not required for automation)
```

## Supported Sections

| Section | Builder | Data Files | Per-Domain? |
|---------|---------|-----------|-----------|
| Forest Summary | Add-AdForestSummary | Forest summary CSV | No |
| Forest Trusts | Add-AdTrustInformation | Trusts CSV | No |
| Forest Sites | Add-AdRawTableFromCsv | Sites CSV | No |
| Forest Subnets | Add-AdRawTableFromCsv | Subnets CSV | No |
| Forest UPN Suffixes | Add-AdRawTableFromCsv | UPN Suffixes CSV | No |
| Domain Summary | Add-AdDomainInformation | Domain summary CSV | Yes |
| Domain Controllers | Add-AdDomainControllers | DC inventory CSV | Yes |
| Domain Users | Add-AdUserStatsSummary | Users CSV | Yes |
| Domain Computers | Add-AdDeviceSummary | Servers + Workstations CSVs | Yes |
| Domain Groups | Add-AdGroupStatsSummary | Groups CSV | Yes |
| Domain Password Policy | Add-AdPasswordPolicies | Default password policy CSV | Yes |
| Domain GPOs | Add-AdGPOSummary | GPO inventory CSV | Yes |
| Domain OUs | Add-AdOuStructureSummary | OUs CSV | Yes |

## Real-World Example

```powershell
# Customer: Transdev
# Discovery output: C:\Customers\Transdev\Source\AD_corp.voyageurtransportation.ca__vts_20260129-123254

$params = @{
  DiscoveryOutputPath = "C:\Customers\Transdev\Source\AD_corp.voyageurtransportation.ca__vts_20260129-123254"
  TemplatePath        = "C:\Templates\AD_Assessment_Corporate.dotx"
  OutputPath          = "C:\Customers\Transdev\Reports\AD_Assessment_20260130.docx"
  TableStyleName      = "Light Grid Accent 1"
  Visible             = $false
}

$result = Invoke-ADAssessmentAutomation @params

if ($result) {
  Write-Host "Assessment created: $result" -ForegroundColor Green
  & $result  # Open in Word
}
```

## Troubleshooting

### Error: "Discovery output path not found"

```
throw "Discovery output path not found: $DiscoveryOutputPath"
```

**Solution**: Verify discovery completed and path is correct:
```powershell
Test-Path "C:\Discovery\AD_forest__vts_20260129-120000\10_forest"
Test-Path "C:\Discovery\AD_forest__vts_20260129-120000\20_domains"
```

### Warning: "CSV not found for section: Domain_Users"

```
Warning: CSV not found for section: Domain_Users (Pattern: *__Identity__Users__Domain-*.csv)
```

**Solution**: Check domain directories exist:
```powershell
Get-ChildItem "C:\Discovery\AD_forest__vts_20260129-120000\20_domains" -Directory
```

### Error: "Builder function not found"

```
Error: Builder function not found: Add-AdForestSummary
```

**Solution**: Import Assessment module:
```powershell
Import-Module "C:\GitHub\Migration.Toolkit\src\Migration.Toolkit.Assessment" -Force
```

## Advanced Usage

### Filtering Specific Sections Only

```powershell
# Only forest and user data
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath $discoveryPath `
  -TemplatePath $template `
  -OutputPath $output `
  -Sections @("Forest_Summary", "Forest_Trusts", "Domain_Users")
```

### Custom Table Styling

```powershell
# Red headers, custom table style
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath $discoveryPath `
  -TemplatePath $template `
  -OutputPath $output `
  -TableStyleName "Light List Accent 1" `
  -HeaderFontColor "CC0000"
```

### Automation in Script

```powershell
function New-CustomerAssessment {
  param(
    [string]$CustomerName,
    [string]$DiscoveryRoot
  )

  $outputDir = Join-Path $DiscoveryRoot ".." "Reports"
  if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

  $outputFile = Join-Path $outputDir "Assessment_$(Get-Date -f yyyyMMdd).docx"

  Invoke-ADAssessmentAutomation `
    -DiscoveryOutputPath $DiscoveryRoot `
    -TemplatePath "C:\Templates\AD_Assessment.dotx" `
    -OutputPath $outputFile

  return $outputFile
}

# Use it
$report = New-CustomerAssessment -CustomerName "Transdev" `
  -DiscoveryRoot "C:\Customers\Transdev\Source\AD_corp__vts_20260129-123254"
```

## Next Steps

1. **Create Word Template** - Add bookmarks for sections (optional but recommended)
2. **Test with Sample Data** - Use the `compare/ADOnly_20260121-132028` directory
3. **Customize ADAssessmentMap.json** - Add/remove sections as needed
4. **Integrate into Scripts** - Wrap in customer-specific automation
5. **Deploy to Customers** - Package with templates and configs

## See Also

- [AD_ASSESSMENT_AUTOMATION.md](AD_ASSESSMENT_AUTOMATION.md) - Full documentation
- [ADAssessmentMap.json](config/ADAssessmentMap.json) - Configuration reference
- [Invoke-ADOnlyAssessment](Public/Invoke-ADOnlyAssessment.ps1) - Manual mode (if needed)
