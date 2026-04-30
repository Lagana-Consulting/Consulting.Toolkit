# Power BI Starter

This folder documents the recommended Power BI Desktop workflow for
`Consulting.Toolkit.Discovery` and `Migration.Toolkit.Analysis`.

For a concrete report build guide, see:

- [PAGE_LAYOUT.md](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Analysis/PowerBI/PAGE_LAYOUT.md>)

## Recommended Flow

1. Export a curated dataset from one or more discovery runs
2. Import the curated CSV tables into Power BI Desktop
3. Build relationships from the stable keys
4. Create visuals from the summary and detail fact tables

## Step 1: Export Curated Tables

Run the analysis module export first:

```powershell
Import-Module "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Analysis" -Force

Export-AdPowerBiDataset `
  -RunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -OutputRoot "F:\Shared\PowerBI\ADDataset"
```

If you also have an analysis workspace:

```powershell
Export-AdPowerBiDataset `
  -RunRoot @(
    "F:\Shared\AD_sourcelab.com_20260423-082040",
    "F:\Shared\AD_targetlab.com_20260423-090000"
  ) `
  -WorkspaceRoot "F:\Shared\AnalysisWorkspace" `
  -OutputRoot "F:\Shared\PowerBI\ADDataset"
```

## Exported Tables

The export writes a curated set of CSVs such as:

- `DimRun`
- `DimDomain`
- `FactRunSummary`
- `FactDomainSummary`
- `FactRiskSummary`
- `FactPasswordPolicy`
- `FactTrusts`
- `FactGpoInventory`
- `FactDomainControllers`
- `FactPrivilegedAccounts`
- `FactServiceAccountCandidates`

Optional workspace tables:

- `FactWorkspaceRuns`
- `FactIdentityCollisions`
- `FactPasswordPolicyDiff`

The export also writes `DatasetManifest.json` so you can see exactly which tables were produced.

## Step 2: Import into Power BI Desktop

Recommended approach:

1. Open Power BI Desktop
2. Choose `Get data`
3. Import each curated CSV from the output folder
4. In Power Query, set data types before loading

Recommended types:

- Keys such as `RunKey` and `RunDomainKey`: Text
- Counts and percentages: Whole Number or Decimal Number
- Timestamps: Date/Time
- Flags and descriptions: Text

## Recommended Relationships

Use these as the starting model:

- `DimRun[RunKey]` 1:* `FactRunSummary[RunKey]`
- `DimRun[RunKey]` 1:* `FactRiskSummary[RunKey]`
- `DimRun[RunKey]` 1:* `DimDomain[RunKey]`
- `DimDomain[RunDomainKey]` 1:* `FactDomainSummary[RunDomainKey]`
- `DimDomain[RunDomainKey]` 1:* `FactPasswordPolicy[RunDomainKey]`
- `DimDomain[RunDomainKey]` 1:* `FactGpoInventory[RunDomainKey]`
- `DimDomain[RunDomainKey]` 1:* `FactDomainControllers[RunDomainKey]`
- `DimDomain[RunDomainKey]` 1:* `FactPrivilegedAccounts[RunDomainKey]`
- `DimDomain[RunDomainKey]` 1:* `FactServiceAccountCandidates[RunDomainKey]`

## Recommended Pages

### 1. Executive Overview

Suggested visuals:

- Cards: `UsersTotal`, `GroupsTotal`, `ComputersTotal`, `DomainsCount`, `TrustCount`
- Clustered column chart: `UsersStaleCount`, `ComputersStaleCount`, `WeakPasswordPoliciesCount`
- Donut chart: `FactRiskSummary[Severity]` by `FactRiskSummary[Count]`
- Matrix: `FactRunSummary` by run/environment

### 2. Domain Posture

Suggested visuals:

- Table or matrix from `FactDomainSummary`
- Bar chart by domain: `UsersTotal`
- Bar chart by domain: `PrivilegedAccountsCount`
- Bar chart by domain: `UsersNonRoutableUPNCount`
- Table: password policy settings from `FactPasswordPolicy`

### 3. Security Findings

Suggested visuals:

- Table: `FactRiskSummary`
- Table: `FactPrivilegedAccounts`
- Table: `FactServiceAccountCandidates`
- Table: `FactDomainControllers`
- Trust posture table from `FactTrusts`

### 4. Change / Comparison

If workspace tables exist:

- Table: `FactIdentityCollisions`
- Table: `FactPasswordPolicyDiff`
- Matrix by `Role`, `Environment`, and `DomainFqdn`

## Starter Measures

Good initial DAX measures:

```DAX
Total Users = SUM(FactRunSummary[UsersTotal])
Total Groups = SUM(FactRunSummary[GroupsTotal])
Total Computers = SUM(FactRunSummary[ComputersTotal])
Stale Users = SUM(FactRunSummary[UsersStaleCount])
Stale Computers = SUM(FactRunSummary[ComputersStaleCount])
Privileged Accounts = SUM(FactRunSummary[PrivilegedAccountsCount])
Risk Count = SUM(FactRiskSummary[Count])
Weak Policy Domains = SUM(FactRunSummary[WeakPasswordPoliciesCount])
```

## Notes

- Start from the curated export, not the raw collector folder, for the first version of the PBIX
- The curated keys make relationships much easier to maintain
- Raw collector CSVs are still useful for drill-through and detail pages later
