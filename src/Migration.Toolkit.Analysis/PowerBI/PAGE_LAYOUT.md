# Power BI Page Layout

This document gives a concrete first-version layout for a Power BI Desktop report
using the curated dataset exported by `Export-AdPowerBiDataset`.

Recommended report settings:

- Canvas: `16:9`
- Theme: use a clean light theme with blue accent for overview visuals
- Default page size: `1280 x 720` or Power BI standard widescreen
- Add a left-aligned report title and a top slicer row on every page

## Model Assumptions

These pages assume the curated export includes:

- `DimRun`
- `DimDomain`
- `FactRunSummary`
- `FactDomainSummary`
- `FactRiskSummary`
- `FactPasswordPolicy`
- `FactGpoInventory`
- `FactDomainControllers`
- `FactPrivilegedAccounts`
- `FactServiceAccountCandidates`

Recommended slicers on every page:

- `DimRun[Environment]`
- `DimRun[RunName]`
- `DimDomain[DomainFqdn]`

## DAX Measures

Create these measures first in `FactRunSummary` unless noted otherwise.

```DAX
Total Users = SUM(FactRunSummary[UsersTotal])

Total Groups = SUM(FactRunSummary[GroupsTotal])

Total Computers = SUM(FactRunSummary[ComputersTotal])

Total Domains = SUM(FactRunSummary[DomainsCount])

Total Trusts = SUM(FactRunSummary[TrustCount])

Total GPOs = SUM(FactRunSummary[GpoCount])

Total OUs = SUM(FactRunSummary[OuCount])

Total Domain Controllers = SUM(FactRunSummary[DomainControllerCount])

Stale Users = SUM(FactRunSummary[UsersStaleCount])

Stale Computers = SUM(FactRunSummary[ComputersStaleCount])

Privileged Accounts = SUM(FactRunSummary[PrivilegedAccountsCount])

Weak Policy Domains = SUM(FactRunSummary[WeakPasswordPoliciesCount])

Non-Routable UPN Users = SUM(FactRunSummary[UsersNonRoutableUPNCount])

AdminSDHolder Protected = SUM(FactRunSummary[AdminSdHolderImpactCount])

Unconstrained Delegation = SUM(FactRunSummary[UnconstrainedDelegationCount])

Service Account Candidates = SUM(FactRunSummary[ServiceAccountCandidatesCount])

ASREP Roastable Users = SUM(FactRunSummary[AsrepRoastableUsersCount])

Risk Count = SUM(FactRiskSummary[Count])

High Risk Count =
CALCULATE(
    SUM(FactRiskSummary[Count]),
    FactRiskSummary[Severity] = "High"
)

Medium Risk Count =
CALCULATE(
    SUM(FactRiskSummary[Count]),
    FactRiskSummary[Severity] = "Medium"
)

Critical Risk Count =
CALCULATE(
    SUM(FactRiskSummary[Count]),
    FactRiskSummary[Severity] = "Critical"
)

Users Stale % =
DIVIDE([Stale Users], [Total Users], 0)

Computers Stale % =
DIVIDE([Stale Computers], [Total Computers], 0)

Privileged Accounts % =
DIVIDE([Privileged Accounts], [Total Users], 0)

Domain Risk Count = SUM(FactDomainSummary[WeakPasswordPoliciesCount])

Domain Users = SUM(FactDomainSummary[UsersTotal])

Domain Computers = SUM(FactDomainSummary[ComputersTotal])

Domain Privileged Accounts = SUM(FactDomainSummary[PrivilegedAccountsCount])

Domain Service Accounts = SUM(FactDomainSummary[ServiceAccountCandidatesCount])

Domain GPOs = SUM(FactDomainSummary[GpoCount])

Domain OUs = SUM(FactDomainSummary[OuCount])

Domain Non-Routable UPN Users = SUM(FactDomainSummary[UsersNonRoutableUPNCount])

Domain AdminSDHolder Protected = SUM(FactDomainSummary[AdminSdHolderImpactCount])
```

Optional score measure for the overview page:

```DAX
Posture Score =
VAR BaseScore = 100
VAR PenaltyHigh = [High Risk Count] * 2
VAR PenaltyMedium = [Medium Risk Count] * 1
VAR PenaltyCritical = [Critical Risk Count] * 5
VAR Score = BaseScore - PenaltyHigh - PenaltyMedium - PenaltyCritical
RETURN MAX(0, Score)
```

## Page 1: Executive Overview

### Layout

- Top row: report title plus 3 slicers
- Row 2: 6 KPI cards
- Row 3 left: risk severity chart
- Row 3 right: posture and hygiene chart
- Bottom: run summary matrix

### Visual 1: KPI Card - Total Users

- Visual type: `Card`
- Measure: `[Total Users]`
- Title: `Users`

### Visual 2: KPI Card - Total Groups

- Visual type: `Card`
- Measure: `[Total Groups]`
- Title: `Groups`

### Visual 3: KPI Card - Total Computers

- Visual type: `Card`
- Measure: `[Total Computers]`
- Title: `Computers`

### Visual 4: KPI Card - Total Domains

- Visual type: `Card`
- Measure: `[Total Domains]`
- Title: `Domains`

### Visual 5: KPI Card - Total Trusts

- Visual type: `Card`
- Measure: `[Total Trusts]`
- Title: `Trusts`

### Visual 6: KPI Card - Posture Score

- Visual type: `Card`
- Measure: `[Posture Score]`
- Title: `Posture Score`

### Visual 7: Risk Severity Breakdown

- Visual type: `Donut chart`
- Legend: `FactRiskSummary[Severity]`
- Values: `[Risk Count]`
- Title: `Risk Severity Breakdown`

Formatting:

- Sort by descending value
- Show data labels
- Suggested colors:
  - Critical: dark red
  - High: orange
  - Medium: amber
  - Low: green

### Visual 8: Risk Flags by Count

- Visual type: `Clustered bar chart`
- Y-axis: `FactRiskSummary[Flag]`
- X-axis: `[Risk Count]`
- Tooltips: `FactRiskSummary[Severity]`, `FactRiskSummary[Description]`
- Title: `Top Findings`

Formatting:

- Sort descending by `[Risk Count]`
- Turn on data labels

### Visual 9: Hygiene Overview

- Visual type: `Clustered column chart`
- X-axis: static category from measures
- Values:
  - `[Stale Users]`
  - `[Stale Computers]`
  - `[Weak Policy Domains]`
  - `[Non-Routable UPN Users]`
  - `[AdminSDHolder Protected]`
  - `[Unconstrained Delegation]`
- Title: `Identity Hygiene and Exposure`

Implementation note:

- In standard Power BI, use a multi-row card if you want quick implementation
- If you want a true chart, create a small disconnected measure-selector table later

### Visual 10: Run Summary Matrix

- Visual type: `Matrix`
- Rows: `DimRun[Environment]`, `DimRun[RunName]`
- Values:
  - `[Total Users]`
  - `[Total Groups]`
  - `[Total Computers]`
  - `[Total Domains]`
  - `[Total Trusts]`
  - `[Total GPOs]`
- Title: `Run Summary`

## Page 2: Domain Posture

### Layout

- Top row: same slicers
- Left half: domain matrix
- Right half top: two ranked bar charts
- Right half bottom: password-policy table
- Bottom full width: domain bubble/scatter

### Visual 1: Domain Summary Matrix

- Visual type: `Matrix`
- Rows: `DimDomain[DomainFqdn]`
- Values:
  - `[Domain Users]`
  - `[Domain Computers]`
  - `[Domain Privileged Accounts]`
  - `[Domain Service Accounts]`
  - `[Domain GPOs]`
  - `[Domain OUs]`
  - `[Domain Non-Routable UPN Users]`
  - `[Domain AdminSDHolder Protected]`
- Title: `Domain Summary`

Conditional formatting:

- `Domain Non-Routable UPN Users`: red background if `> 0`
- `Domain AdminSDHolder Protected`: orange background if `> 0`
- `Domain Service Accounts`: amber background if `> 5`

### Visual 2: Users by Domain

- Visual type: `Clustered bar chart`
- Y-axis: `DimDomain[DomainFqdn]`
- X-axis: `[Domain Users]`
- Tooltips:
  - `[Domain Computers]`
  - `[Domain GPOs]`
  - `[Domain OUs]`
- Title: `Users by Domain`

### Visual 3: Privileged Accounts by Domain

- Visual type: `Clustered bar chart`
- Y-axis: `DimDomain[DomainFqdn]`
- X-axis: `[Domain Privileged Accounts]`
- Tooltips:
  - `[Domain Service Accounts]`
  - `[Domain AdminSDHolder Protected]`
- Title: `Privileged Accounts by Domain`

### Visual 4: Password Policy Table

- Visual type: `Table`
- Columns:
  - `FactPasswordPolicy[DomainFqdn]`
  - `FactPasswordPolicy[ComplexityEnabled]`
  - `FactPasswordPolicy[MinPasswordLength]`
  - `FactPasswordPolicy[PasswordHistoryCount]`
  - `FactPasswordPolicy[MaxPasswordAgeDays]`
  - `FactPasswordPolicy[LockoutThreshold]`
  - `FactPasswordPolicy[ReversibleEncryptionEnabled]`
- Title: `Default Password Policy by Domain`

Conditional formatting:

- `MinPasswordLength`: red if `< 12`
- `MaxPasswordAgeDays`: amber if `> 90` or `= 0`
- `ReversibleEncryptionEnabled`: red if `True`

### Visual 5: Domain Complexity Scatter

- Visual type: `Scatter chart`
- X-axis: `[Domain Users]`
- Y-axis: `[Domain Computers]`
- Size: `[Domain GPOs]`
- Details: `DimDomain[DomainFqdn]`
- Legend: `DimRun[Environment]`
- Tooltips:
  - `[Domain OUs]`
  - `[Domain Service Accounts]`
  - `[Domain Privileged Accounts]`
- Title: `Domain Size and Complexity`

## Page 3: Security and Operations

### Layout

- Top row: same slicers
- Left column: security findings and privileged account detail
- Right column: service accounts and domain controllers
- Bottom: GPO and trust detail

### Visual 1: Security Findings Table

- Visual type: `Table`
- Columns:
  - `FactRiskSummary[Severity]`
  - `FactRiskSummary[Flag]`
  - `FactRiskSummary[Count]`
  - `FactRiskSummary[Description]`
  - `FactRiskSummary[Recommendation]`
- Title: `Security Findings`

Sorting:

- Sort by `Severity`, then `Count` descending

### Visual 2: Privileged Accounts Table

- Visual type: `Table`
- Columns:
  - `FactPrivilegedAccounts[DomainFqdn]`
  - `FactPrivilegedAccounts[SamAccountName]`
  - `FactPrivilegedAccounts[InPrivGroups]`
  - `FactPrivilegedAccounts[PrivGroups]`
  - `FactPrivilegedAccounts[AdminCount]`
- Title: `Privileged Accounts`

### Visual 3: Service Account Candidates Table

- Visual type: `Table`
- Columns:
  - `FactServiceAccountCandidates[DomainFqdn]`
  - `FactServiceAccountCandidates[SamAccountName]`
  - `FactServiceAccountCandidates[Enabled]`
  - `FactServiceAccountCandidates[HeuristicFlags]`
  - `FactServiceAccountCandidates[PasswordAgeDays]`
  - `FactServiceAccountCandidates[LastLogonDays]`
  - `FactServiceAccountCandidates[Description]`
- Title: `Service Account Candidates`

### Visual 4: Domain Controller Inventory

- Visual type: `Table`
- Columns:
  - `FactDomainControllers[DomainFqdn]`
  - `FactDomainControllers[Name]`
  - `FactDomainControllers[HostName]`
  - `FactDomainControllers[Site]`
  - `FactDomainControllers[OperatingSystem]`
  - `FactDomainControllers[IsGlobalCatalog]`
  - `FactDomainControllers[IsReadOnly]`
  - `FactDomainControllers[IsEnabled]`
- Title: `Domain Controllers`

### Visual 5: GPO Inventory

- Visual type: `Table`
- Columns:
  - `FactGpoInventory[DomainFqdn]`
  - `FactGpoInventory[DisplayName]`
  - `FactGpoInventory[Owner]`
  - `FactGpoInventory[GpoStatus]`
  - `FactGpoInventory[CreationTime]`
  - `FactGpoInventory[ModificationTime]`
- Title: `Group Policy Inventory`

### Visual 6: Trust Inventory

- Visual type: `Table`
- Columns:
  - `FactTrusts[Name]`
  - `FactTrusts[Source]`
  - `FactTrusts[Target]`
  - `FactTrusts[Direction]`
  - `FactTrusts[TrustType]`
  - `FactTrusts[ForestTransitive]`
  - `FactTrusts[SelectiveAuthentication]`
  - `FactTrusts[UsesAESKeys]`
  - `FactTrusts[UsesRC4Encryption]`
- Title: `Trust Inventory`

## Build Order

Recommended order in Desktop:

1. Import curated CSVs
2. Create relationships
3. Create all DAX measures
4. Build Page 1 first
5. Copy slicers to Page 2 and Page 3
6. Add conditional formatting and titles last

## First PBIX Goal

For the first usable PBIX, build only these visuals:

- Page 1: KPI cards, risk donut, findings bar chart, run matrix
- Page 2: domain matrix, users by domain, password policy table
- Page 3: security findings table, privileged accounts table, domain controllers table

That gets you a useful executive + operational report quickly without overbuilding version 1.
