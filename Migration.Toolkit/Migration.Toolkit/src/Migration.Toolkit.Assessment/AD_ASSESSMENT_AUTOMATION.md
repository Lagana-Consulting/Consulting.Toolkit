# AD Assessment Automation Strategy

## Overview

The `Invoke-ADAssessmentAutomation` function provides end-to-end automation for generating comprehensive AD assessments from Discovery Toolkit output.

**Key Innovation**: Maps the structured Discovery output directory hierarchy to Assessment module table builders, eliminating manual CSV selection and function calling.

## Discovery Output Structure

Discovery Toolkit creates standardized output directories with this structure:

```
AD_<forest>__vts_<timestamp>/
├── 00_schemas/               # Column definitions (metadata)
│   ├── Schema_Forest_Summary.csv
│   ├── Schema_Domain_Summary.csv
│   └── ... (18 total schema definitions)
├── 10_forest/               # Forest-level data
│   ├── LC__AD__Forest__Summary__Forest.csv
│   ├── LC__AD__Forest__Security__Trusts__Forest.csv
│   ├── LC__AD__Forest__Network__Sites__Forest.csv
│   ├── LC__AD__Forest__Network__Subnets__Forest.csv
│   ├── LC__AD__Forest__Identity__UpnSuffixes__Forest.csv
│   └── ... (11 total forest files)
├── 20_domains/              # Per-domain data
│   ├── Domain-sourcelab.com/
│   │   ├── LC__AD__Domain__Summary__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__Users__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__ComputersServers__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__ComputersWorkstations__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Identity__Groups__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Security__PasswordPolicyDefault__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__GPO__Inventory__Domain-sourcelab.com.csv
│   │   ├── LC__AD__Domain__Structure__OrganizationalUnits__Domain-sourcelab.com.csv
│   │   └── ... (35 total per-domain files)
│   └── Domain-child1.sourcelab.com/
│       └── ... (same structure per domain)
└── 99_manifest/             # Execution metadata
    └── Manifest.xml
```

## Configuration: ADAssessmentMap.json

The `ADAssessmentMap.json` file defines the mapping between Discovery output files and Assessment table builders.

### Section Definition Structure

```json
{
  "Id": "Forest_Trusts",
  "Title": "Forest Trusts",
  "Category": "Infrastructure",              // "Infrastructure" or "PerDomain"
  "Builder": "Add-AdTrustInformation",       // Assessment function to call
  "DataSource": {
    "Path": "10_forest",                      // Relative to discovery root
    "Pattern": "*__Security__Trusts__Forest.csv",
    "Single": true,                           // Forest-level vs per-domain
    "PerDomain": false
  },
  "Columns": ["Name", "Direction", "TrustType", ...],  // Optional column filtering
  "Mode": "Table",                            // "MetricValue" or "Table"
  "Parameters": {                             // Optional builder-specific params
    "Mode": "Rollup",
    "ActiveThresholdDays": 90
  }
}
```

### Current Mapped Sections

| Section ID | Title | Builder | Data Source | Mode |
|-----------|-------|---------|-------------|------|
| Forest_Summary | Forest Summary | Add-AdForestSummary | 10_forest/*__Summary__Forest.csv | MetricValue |
| Forest_Trusts | Forest Trusts | Add-AdTrustInformation | 10_forest/*__Security__Trusts__Forest.csv | Table |
| Forest_Sites | Replication Sites | Add-AdRawTableFromCsv | 10_forest/*__Network__Sites__Forest.csv | Table |
| Domain_Summary | Domain Summary | Add-AdDomainInformation | 20_domains/{Domain}/*__Domain__Summary__Domain-*.csv | MetricValue |
| Domain_Controllers | Domain Controllers | Add-AdDomainControllers | 20_domains/{Domain}/*__Infrastructure__DomainControllers__Domain-*.csv | Table |
| Domain_Users | Users Summary | Add-AdUserStatsSummary | 20_domains/{Domain}/*__Identity__Users__Domain-*.csv | MetricValue |
| Domain_Computers | Device Summary | Add-AdDeviceSummary | 20_domains/{Domain}/*__Identity__Computers*.csv | MetricValue |
| Domain_Groups | Groups Summary | Add-AdGroupStatsSummary | 20_domains/{Domain}/*__Identity__Groups__Domain-*.csv | Table |
| Domain_PasswordPolicy | Default Password Policy | Add-AdPasswordPolicies | 20_domains/{Domain}/*__Security__PasswordPolicyDefault__Domain-*.csv | MetricValue |
| Domain_GPO | GPO Summary | Add-AdGPOSummary | 20_domains/{Domain}/*__Domain__GPO__Inventory__Domain-*.csv | MetricValue |
| Domain_OUs | Organizational Units | Add-AdOuStructureSummary | 20_domains/{Domain}/*__Structure__OrganizationalUnits__Domain-*.csv | MetricValue |

## Usage

### Basic Usage

```powershell
# Minimal - uses defaults
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath "C:\Discovery\AD_forest__vts_20260129-120000" `
  -TemplatePath "C:\Templates\AD_Assessment.dotx" `
  -OutputPath "C:\Reports\Assessment.docx"
```

### Advanced Usage with Options

```powershell
# With custom styling and specific sections
Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath "C:\Discovery\AD_forest__vts_20260129-120000" `
  -TemplatePath "C:\Templates\AD_Assessment.dotx" `
  -OutputPath "C:\Reports\Assessment.docx" `
  -TableStyleName "Light Grid Accent 1" `
  -HeaderFontColor "FF0000" `
  -Visible `
  -Sections @("Forest_Summary", "Domain_Users", "Domain_Computers")
```

### Discovery Output from Customer Directory

```powershell
# If discovery output is in customer folder:
$discoveryPath = "C:\Customers\Transdev\Source\AD_corp.voyageurtransportation.ca__vts_20260129-123254"

Invoke-ADAssessmentAutomation `
  -DiscoveryOutputPath $discoveryPath `
  -TemplatePath "C:\Templates\AD_Assessment.dotx" `
  -OutputPath "C:\Customers\Transdev\Reports\Assessment_$(Get-Date -f yyyyMMdd).docx"
```

## How It Works

### 1. Discovery Phase

The function scans the input directory structure:

```powershell
# Discovers forest-level files
Find-ForestCsv -Pattern "*__Security__Trusts__Forest.csv" -RootPath $DiscoveryOutputPath

# Discovers domain directories
Find-DomainDirectories -RootPath $DiscoveryOutputPath

# For each domain, discovers domain-specific files
Find-DomainCsv -Pattern "*__Identity__Users__Domain-*.csv" -DomainPath "Domain-sourcelab.com" -DomainName "sourcelab.com"
```

### 2. Mapping Phase

Each discovered CSV is mapped to a section context:

```powershell
@{
  Id = "Forest_Trusts"
  Title = "Forest Trusts"
  Builder = "Add-AdTrustInformation"
  DataFiles = @{ CsvPath = "C:\Discovery\...\LC__AD__Forest__Security__Trusts__Forest.csv" }
}
```

### 3. Generation Phase

For each section context, the appropriate Assessment function is called:

```powershell
# Example: Forest Trusts section
& Add-AdTrustInformation `
  -Document $doc `
  -Title "Forest Trusts" `
  -CsvPath "C:\Discovery\...\LC__AD__Forest__Security__Trusts__Forest.csv" `
  -TableStyleName "Light Grid Accent 1"
```

### 4. Document Assembly

Tables are inserted sequentially into the Word document, either:
- **To template bookmarks** if template has defined bookmarks (future: Invoke-ADOnlyAssessment with template)
- **End of document** (current: sequential insertion)

## Integration Points

### With Word Template

For best results, create a Word template with bookmarks:

```
Bookmark Name                Corresponds To
=====================        ====================
Forest_Summary               Forest Summary section
Forest_Trusts                Trust relationships
Domain_Summary              Domain metadata
Domain_Users                User statistics
Domain_Computers            Device/computer summary
Domain_Groups               Group statistics
Domain_PasswordPolicy        Password policy
Domain_GPO                  GPO metrics
Domain_OUs                  OU structure
```

Template insertion:

```powershell
$range = Get-AdBookmarkRange -Document $doc -BookmarkName "Forest_Summary"
$range.Text = ""
$range.Collapse(0)
# Insert content at $range
```

### Extending ADAssessmentMap.json

To add new sections:

```json
{
  "Id": "Domain_SPN",
  "Title": "Service Principal Names",
  "Category": "PerDomain",
  "Builder": "Add-AdRawTableFromCsv",
  "DataSource": {
    "Path": "20_domains/{Domain}",
    "Pattern": "*__Identity__Spns__Domain-*.csv",
    "Single": false,
    "PerDomain": true
  },
  "Columns": ["Name", "ObjectClass", "ServicePrincipalName"],
  "Mode": "Table"
}
```

Then call with the new section:

```powershell
Invoke-ADAssessmentAutomation ... -Sections @("Forest_Summary", "Domain_SPN")
```

## Troubleshooting

### CSV Not Found

```
Warning: CSV not found for section: Forest_Trusts (Pattern: *__Security__Trusts__Forest.csv)
```

**Solution**: Check if discovery process completed successfully. Verify file naming matches expected pattern.

### Builder Function Not Found

```
Warning: Builder function not found: Add-AdTrustInformation
```

**Solution**: Ensure Assessment module is imported: `Import-Module Migration.Toolkit.Assessment`

### Column Mismatch

If CSV columns differ from table builder expectations, specify `Columns` in ADAssessmentMap.json to filter/rename columns.

## Performance Considerations

- **Discovery**: ~1-2 seconds for typical 2-3 domain forest
- **Document Generation**: ~3-5 seconds per domain (varies with table size)
- **Total Time**: ~15-30 seconds for complete assessment (excludes Word startup)

## Future Enhancements

1. **Template Bookmark Support** - Insert tables to specific bookmarks instead of sequential
2. **Section Ordering** - Custom section order in config
3. **Conditional Sections** - Skip sections if CSV empty or criteria not met
4. **Custom Aggregations** - User-defined rollups/pivots in config
5. **Multi-Forest Support** - Process multiple forests in single run
6. **HTML Export** - Alternative output format
7. **Custom Styling Rules** - Conditional formatting based on risk/metrics

## See Also

- [ADAssessmentMap.json](ADAssessmentMap.json) - Configuration reference
- [Invoke-ADOnlyAssessment](../Public/Invoke-ADOnlyAssessment.ps1) - Manual section insertion
- [Add-AdForestSummary](../Public/Add-AdForestSummary.ps1) - Example table builder
- Migration.Toolkit.Discovery - Source of CSV data
