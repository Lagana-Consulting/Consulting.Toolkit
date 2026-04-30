# Migration.Toolkit.Analysis

## Start Here

The easiest way to run the current analysis workflow is the wrapper script:

[run-analysis.ps1](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/Public/run-analysis.ps1>)

It imports the local module and runs the common reporting flow against current
`Consulting.Toolkit.Discovery` output.

If you want the primary deliverable as **HTML + structured data**, use:

[run-assessment-package.ps1](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/Public/run-assessment-package.ps1>)

That package workflow produces:
- HTML assessment reports
- a package landing page
- an optional curated structured dataset
- an optional shared cross-run workspace
- an optional customer-facing package without structured data or workspace artifacts
- a customer handoff folder with `index.html`, `README.txt`, and a `Reports` folder
- an optional customer zip archive created with `-ZipCustomerPackage`
- a neutral starter template in [ExecutiveSummary.Config.Standard.json](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/config/ExecutiveSummary.Config.Standard.json>)
- optional executive-summary consultant overrides from [ExecutiveSummary.Config.example.json](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/config/ExecutiveSummary.Config.example.json>)
- a reusable live example for current customer work in [ExecutiveSummary.Config.Versetal.json](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/config/ExecutiveSummary.Config.Versetal.json>)

For each source run it can generate:
- Executive assessment report
- Migration preparation report
- Optional comprehensive assessment report
- Analysis workspace from `Invoke-AdDiscoveryAnalysis`

If you also provide a target run, it can additionally generate:
- Environment comparison report per source
- Migration readiness checklist per source

## Common Usage

Source-only run:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-analysis.ps1" `
  -SourceRunRoot "F:\Shared\AD_sourcelab.com_20260423-082040"
```

Source-only reports without workspace generation:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-analysis.ps1" `
  -SourceRunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -SkipWorkspace
```

Source and target comparison:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-analysis.ps1" `
  -SourceRunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -TargetRunRoot "F:\Shared\AD_targetlab.com_20260423-090000" `
  -CustomerName "Lab"
```

Multiple source runs with a shared target:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-analysis.ps1" `
  -SourceRunRoot @(
    "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723",
    "F:\Versetal\lighthouse\Discovery\AD_lighthouseoptics.local__lighthouseoptical_20260428-141625"
  ) `
  -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
  -OutputRoot "F:\Versetal\AssessmentOutputs" `
  -WorkspaceRoot "F:\Versetal\AnalysisWorkspace_Versetal" `
  -CustomerName "Versetal"
```

Assessment package example:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-assessment-package.ps1" `
  -SourceRunRoot @(
    "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723",
    "F:\Versetal\lighthouse\Discovery\AD_lighthouseoptics.local__lighthouseoptical_20260428-141625"
  ) `
  -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
  -OutputRoot "F:\Versetal\AssessmentPackage" `
  -CustomerName "Versetal" `
  -IncludeComprehensiveReport
```

Assessment package with executive-summary consultant input:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-assessment-package.ps1" `
  -SourceRunRoot "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723" `
  -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
  -OutputRoot "F:\Versetal\AssessmentPackage" `
  -CustomerName "Versetal" `
  -ExecutiveSummaryConfigPath "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\config\ExecutiveSummary.Config.Versetal.json" `
  -CreateCustomerPackage
```

For future customers, start with [ExecutiveSummary.Config.Standard.json](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/config/ExecutiveSummary.Config.Standard.json>) and update the `Metadata`, `Defaults`, and `PerForest` entries for the new engagement. Use [ExecutiveSummary.Config.Versetal.json](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/config/ExecutiveSummary.Config.Versetal.json>) as a live example of a filled-in engagement file.

Customer-friendly package example:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-assessment-package.ps1" `
  -SourceRunRoot @(
    "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723",
    "F:\Versetal\lighthouse\Discovery\AD_lighthouseoptics.local__lighthouseoptical_20260428-141625"
  ) `
  -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
  -OutputRoot "F:\Versetal\AssessmentPackage" `
  -CustomerName "Versetal" `
  -CreateCustomerPackage `
  -ZipCustomerPackage
```

If you want the internal package without structured data:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-assessment-package.ps1" `
  -SourceRunRoot "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723" `
  -OutputRoot "F:\Versetal\AssessmentPackage_NoData" `
  -CustomerName "Versetal" `
  -SkipStructuredData `
  -SkipWorkspace
```

Examples


```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-assessment-package.ps1" `
    -SourceRunRoot @(
    "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723",
    "F:\Versetal\lighthouse\Discovery\AD_lighthouseoptics.local__lighthouseoptical_20260428-141625") `
    -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
    -OutputRoot "F:\Versetal\AssessmentPackage_Internal" `
    -CustomerName "Versetal" `
    -ExecutiveSummaryConfigPath "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\config\ExecutiveSummary.Config.Versetal.json" `
    -IncludeComprehensiveReport
```

```powershell 
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-assessment-package.ps1" `
    -SourceRunRoot @(
    "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723",
    "F:\Versetal\lighthouse\Discovery\AD_lighthouseoptics.local__lighthouseoptical_20260428-141625") `
    -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
    -OutputRoot "F:\Versetal\AssessmentPackage_Customer" `
    -CustomerName "Versetal" `
    -ExecutiveSummaryConfigPath "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\config\ExecutiveSummary.Config.Versetal.json" `
    -CreateCustomerPackage `
    -SkipStructuredData `
    -ZipCustomerPackage `
    -SkipWorkspace
```

## Notes

- With one source run, output defaults to `<SourceRunRoot>\40_assessment`
- With multiple source runs, output defaults to `AnalysisOutputs_<timestamp>` under the current directory
- The workspace defaults to `AnalysisWorkspace_<timestamp>` under the output folder
- The script includes comment-based help, so this also works:

```powershell
Get-Help "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis\Public\run-analysis.ps1" -Full
```
