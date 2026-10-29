# Consulting.Toolkit.Discovery

`Consulting.Toolkit.Discovery` is a PowerShell module for collecting Active
Directory discovery inventory into structured CSV outputs. It is intended to
create evidence-ready discovery run folders that can be passed into downstream
analysis, assessment, planning, or Power BI workflows.

The discovery collector writes data only. It does not apply remediation, perform
migration readiness scoring, compare environments, or generate HTML reports.

## Quick Start

Open PowerShell from a machine that can query Active Directory, then import the
module:

```powershell
Import-Module "C:\scripts\Consulting.Toolkit.Discovery\Consulting.Toolkit.Discovery.psd1" -Force
```

Run discovery for the current forest:

```powershell
Invoke-AdDiscoveryExport `
  -Environment Source `
  -OutputRoot "C:\Discovery" `
  -CustomerName "CustomerName"
```

Run discovery through a specific domain controller:

```powershell
Invoke-AdDiscoveryExport `
  -Environment Source `
  -OutputRoot "C:\Discovery" `
  -CustomerName "CustomerName" `
  -Server "dc01.contoso.com"
```

Include the optional security-focused collectors:
Import-Module "C:\scripts\Consulting.Toolkit.Discovery\Consulting.Toolkit.Discovery.psd1" -Force

```powershell
Invoke-AdDiscoveryExport `
  -Environment Lighthouseoptics `
  -OutputRoot "C:\scripts\Discovery" `
  -CustomerName "CustomerName" `
  -IncludeSecurity
```

The command prints the completed `RunRoot` and the generated discovery index
path when the run finishes.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- Network line of sight to the Active Directory domain controllers
- RSAT Active Directory PowerShell module available on the runner
- Permissions to read AD objects, GPO data, trusts, sites, replication metadata,
  and other inventory targets
- Write access to the selected `-OutputRoot`

Check the AD module before running:

```powershell
Import-Module ActiveDirectory
Get-Command Get-ADForest, Get-ADDomain, Get-ADUser, Get-ADComputer
```

For broader collection quality, run from a domain-joined administrative
workstation or management server using an account with read access across every
domain in the forest.

## Commands

- `Invoke-AdDiscoveryExport` - full discovery run command with
  `Discovery.Index.json` generation
- `Get-AdAdForest`
- `Get-AdAdDomains`
- `Get-AdAdDomainContext`
- `New-AdRunLayout`
- `Export-AdCsvSafe`
- `Export-AdSchemas`
- `Get-AdComputerStatusDetails`
- `Get-AdGroupMembershipDetails`
- `Get-AdSchemaDefinitions`
- `Get-AdUserStatusDetails`
- `New-AdLog`
- `Write-AdLog`

The manifest defines these 13 supported exports. Import verifies that every
declared command is available. Other collectors are internal implementation
functions used by `Invoke-AdDiscoveryExport`.

## Output Structure

Each run creates a timestamped folder under `-OutputRoot`. The folder name is
derived from the discovered forest root domain and environment label.

Example:

```text
C:\Discovery\AD_contoso.com_20260520-143012\
```

Important subfolders:

```text
00_schemas\       CSV schema definitions
10_forest\        forest-level datasets
20_domains\       per-domain datasets
90_logs\          collector logs
99_manifest\      run manifest, run info, and Discovery.Index.json
```

Key manifest files:

- `99_manifest\Run__Info__Run.csv`
- `99_manifest\Run__Manifest__Run.csv`
- `99_manifest\Run__ExecutionStatus__Run.csv`
- `99_manifest\Discovery.Index.json`

## Common Run Patterns

Source environment discovery:

```powershell
Invoke-AdDiscoveryExport `
  -Environment Source `
  -OutputRoot "D:\Discovery\Source" `
  -CustomerName "Contoso"
```

Target environment discovery:

```powershell
Invoke-AdDiscoveryExport `
  -Environment Target `
  -OutputRoot "D:\Discovery\Target" `
  -CustomerName "Contoso"
```

Capture the result object for automation:

```powershell
$result = Invoke-AdDiscoveryExport `
  -Environment Source `
  -OutputRoot "C:\Discovery" `
  -CustomerName "Contoso"

$result.RunRoot
```

Check `$result.Status` before treating a run as successful. `Partial` means an
operation failed, coverage was incomplete or skipped, or diagnostic logging
failed. Independent datasets continue to export after a failure.
`$result.FailedOperations` contains errors; `$result.IncompleteOperations`
identifies incomplete or skipped operations. User and computer status detail
exports are skipped if their source collection failed. `$result.LoggingFailed`
and `$result.LoggingErrors` identify diagnostic persistence problems.

Diagnostics are correlated by `$result.RunId`:

- `$result.LogPath`: readable log under `90_logs`.
- `$result.DiagnosticLogPath`: JSON Lines events written immediately, including
  operation starts/ends, UTC timestamps, duration, CSV filenames, row counts,
  bytes, selected domain/server, retries, and full error locations/stack traces.
- `$result.ExecutionStatusPath`: CSV snapshot in `99_manifest`, including
  `START`, `OK`, `EMPTY`, `SKIP`, `PARTIAL`, and `FAIL` operation records.

`EMPTY` means collection succeeded with zero rows. `SKIP` means collection was
not attempted or a required cmdlet was unavailable. `PARTIAL` can accompany a
populated CSV when some objects could not be read. Recovered retries retain
an original error without making the operation fail. Retries always specify an
endpoint: either the selected DC or the requested domain's FQDN. A domain FQDN
lets AD locate a DC in that domain; it never uses the runner's implicit domain.
Query events record the explicit endpoint used.

Domain contexts validate the server's default naming context before collection.
Domain searches use an explicit search base, and core collectors reject rows
whose distinguished names belong to another domain. Every entry passed to
`-Domain` must exist in the discovered forest; a partially matching list stops
before data collection. Contacts, forest replication/trust reads, OU ACLs, and
ADCS reads honor the selected target. A forest DC supplied to `-Server` is not
reused for child-domain collection when its naming context differs.

Whole-query access failures produce `FAIL`, rather than empty successful
datasets. Unreadable members, nested groups, certificate-template ACLs, or
privileged-account details produce `PARTIAL` coverage and retain readable rows.
Diagnostics preserve each affected object and original error. A confirmed
`ADIdentityNotFoundException` for an optional privileged group is logged as
absent; permission and connectivity errors are not treated as missing groups.

Run context records PowerShell/module versions, machine/account, requested
options, and a SHA256 fingerprint of the collector source. Startup diagnostics
begin under `<OutputRoot>\90_logs` before forest discovery, then move into the
run folder. A fatal startup error leaves them in that initial location and
prints their paths. JSON Lines events also cover index generation and final run
status; on success the CSV snapshot is finalized before indexing so its index
hash remains valid. If the process is interrupted, inspect the JSON Lines file
for the last `START` without a matching terminal event.

## CSV Contracts

The 60 registered schemas describe the fields emitted by their collectors.
`Export-AdCsvSafe` applies a schema when `-SchemaName` is supplied or when the
output filename matches a registered discovery dataset. With `-AllowEmpty`, a
schema-bound empty dataset produces a header-only CSV. Unmapped filenames keep
their input columns unless an explicit schema is supplied.

Every schema column must exist on each input row; an explicit null value is
valid when the value is unknown. A missing property stops the export before an
existing CSV is overwritten. `Export-AdSchemas -Include` also rejects unknown
schema names before writing files.

SPN inventory includes canonical `ServicePrincipalName` and `ObjectClass`
columns alongside the existing `SPN` and `ObjectType` aliases. Internal SPN
analysis accepts either representation and can consume supplied rows without
querying AD again. Duplicate detection counts distinct account owners.
Security SPN inventory includes account enabled state and UTC password-change
time; unknown values remain blank.

The privileged-account schema preserves `InPrivGroups`, `PrivGroups`, and
`AdminCount`. Empty-group schemas describe the group-membership collector's
actual fields. GPO inventory exposes both `Id` and `GpoId`, and its user and
computer versions are numeric so analysis also works after CSV import.

## Troubleshooting

If module import fails, confirm the path points to the `.psd1` file.

If discovery cannot find AD commands, install or enable RSAT Active Directory
tools on the runner and import the AD module:

```powershell
Import-Module ActiveDirectory
```

If forest discovery fails, try specifying a reachable domain controller:

```powershell
Invoke-AdDiscoveryExport `
  -Environment Source `
  -OutputRoot "C:\Discovery" `
  -Server "dc01.contoso.com"
```

If some datasets are empty or missing, review
`99_manifest\Run__ExecutionStatus__Run.csv` and the log at `$result.LogPath`, and
confirm the running account has read access for that data area. A successfully
generated discovery index does not by itself mean every dataset was collected.

Local regression checks (mocked AD queries, real export and logging code):

```powershell
& .\Tests\Invoke-AdDiscoveryExport.Regression.ps1
& .\Tests\DiscoveryDiagnostics.Module.Tests.ps1
& .\Tests\DiscoveryTargetIntegrity.Tests.ps1
& .\Tests\DiscoveryContracts.Tests.ps1
```

The contract suite checks all declared exports and registered schema shapes,
then exercises collectors, CSV round trips, and consumers with empty, single-row,
and multi-row mocked directory datasets. Run the checks in both Windows
PowerShell 5.1 and PowerShell 7 when changing module contracts.
