# Migration.Toolkit.Planning

`Migration.Toolkit.Planning` is an internal-use module for preparing migration
work, not for customer-facing assessment delivery.

The first MVP focuses on:
- prerequisite validation from current discovery output
- default include file creation
- default exclude and review file creation
- packaging those planning artifacts into one repeatable folder structure
- optional customer handoff packaging with plain-language instructions and zip export

## Start Here

Use the wrapper:

[run-planning.ps1](</C:/Users/paull/OneDrive - Lagana Consulting/Documents/GitHub/Consulting.Toolkit/src/Migration.Toolkit.Planning/Public/run-planning.ps1>)

Example:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Planning\Public\run-planning.ps1" `
  -SourceRunRoot @(
    "F:\Versetal\rossoptical\Discovery\AD_rossoptical.local__rossoptical_20260428-085723",
    "F:\Versetal\lighthouse\Discovery\AD_lighthouseoptics.local__lighthouseoptical_20260428-141625"
  ) `
  -TargetRunRoot "F:\Versetal\poc.local\discovery\AD_poc.local__poc.local_20260428-142453" `
  -OutputRoot "F:\Versetal\MigrationPlanning" `
  -CustomerName "Versetal"
```

If you want the default user include file to keep users with non-routable UPN
suffixes in scope, add:

```powershell
  -IncludeNonRoutableUpnUsers
```

If you want a customer-friendly handoff package and a zip you can send:

```powershell
  -CreateCustomerPackage `
  -ZipCustomerPackage
```

## Current Commands

- `Test-AdMigrationPrerequisites`
- `New-AdMigrationIncludeFile`
- `New-AdMigrationExcludeFile`
- `New-AdMigrationPlanningPackage`

## What the package contains

- `prerequisites`
  - checklist-style CSV and JSON output
- `sources\<source label>`
  - include users
  - include groups
  - include computers
  - exclude candidates
  - a consolidated user-account review file with category flags instead of duplicate user rows across multiple review CSVs
  - duplicate-conflict review when a target run is supplied
- optional `customer`
  - plain-language `index.html`
  - `README.txt`
  - `Customer-Action-Checklist.csv`
  - customer-friendly copies of the source review files
  - empty `CustomerDecision`, `Owner`, `Comment`, and `RequiredAction` columns added to the customer-facing CSVs so they can be filled in directly in Excel

## Current assumptions

- include files are default wave candidates, not final migration scope
- service accounts and privileged accounts are moved into a consolidated review file instead of being duplicated across separate CSVs
- stale and disabled objects are pushed into the exclude/review path
- users with non-routable UPN suffixes are excluded from the default user include file unless `-IncludeNonRoutableUpnUsers` is used
- duplicate conflicts depend on `Migration.Toolkit.Analysis` being present beside this module

## Next likely additions

- ADMT-ready export formats
- prerequisite checks tied to specific migration tooling
- wave modeling
- transformation mapping files
- SQL-backed planning data
