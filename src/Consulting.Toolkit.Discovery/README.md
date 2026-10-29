# Consulting.Toolkit.Discovery

`Consulting.Toolkit.Discovery` is a PowerShell module for collecting Active
Directory discovery inventory into structured CSV outputs. It is intended to
create evidence-ready discovery run folders that can be passed into downstream
analysis, assessment, planning, or Power BI workflows.

The discovery collector writes data only. It does not apply remediation, perform
migration readiness scoring, compare environments, or generate HTML reports.

## Quick Start

To use the Windows GUI, double-click `Start-AdDiscoveryGui.cmd` in the module
folder, or launch it from PowerShell:

```powershell
& .\Start-AdDiscoveryGui.ps1
```

After importing the module, the GUI is also available with:

```powershell
Show-AdDiscoveryGui
```

The GUI opens without querying AD. Configure the options, then select
**Start discovery** to collect inventory. The command-line workflow below remains
available.

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

Use an alternate directory account with a secure PowerShell prompt:

```powershell
$credential = Get-Credential -UserName 'CONTOSO\DiscoveryReader'
Invoke-AdDiscoveryExport `
  -OutputRoot 'C:\Discovery' `
  -Server 'dc01.contoso.com' `
  -Credential $credential `
  -IncludeSecurity
```

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
- `Show-AdDiscoveryGui` - Windows desktop discovery launcher
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

The manifest defines these 14 supported exports. Import verifies that every
declared command is available. Other collectors are internal implementation
functions used by `Invoke-AdDiscoveryExport`.

## Discovery GUI

The Configure tab exposes every discovery parameter:

| GUI field | Command parameter | Behavior |
| --- | --- | --- |
| Environment | `-Environment` | Editable label; defaults to Source |
| Output folder | `-OutputRoot` | Absolute local or UNC path with a folder browser; defaults to `C:\Discovery` |
| Customer name | `-CustomerName` | Optional run metadata |
| Domain controller / server | `-Server` | Optional initial DC; blank selects automatically |
| Domains to collect | `-Domain` | DNS names separated by lines, commas, semicolons, or spaces; blank collects all forest domains |
| Include security inventory | `-IncludeSecurity` | Enables optional security collectors |
| Use alternate directory credentials | `-Credential` | Account name plus a masked password field; uses an isolated network logon session |

Advanced PowerShell options include all common parameters available in the
selected engine: Verbose, Debug, stream action preferences, stream variables,
OutBuffer, and PipelineVariable. PowerShell 7.4+ also exposes ProgressAction.
These options apply within the background runner. Interactive preferences such
as Inquire cannot prompt through the GUI and can fail in the noninteractive
runner. Persistent troubleshooting output is available through the logs.

The command preview updates as fields change and can be copied. **Save settings**
and **Load settings** use JSON files; a saved configuration can also be opened
directly:

```powershell
Show-AdDiscoveryGui -SettingsPath 'C:\Discovery\Customer.settings.json'
```

Select Windows PowerShell 5.1 (recommended for native RSAT modules) or an available
PowerShell 7 installation. By default, discovery uses the signed-in Windows
account. The GUI does not install RSAT or change directory permissions.

For alternate access, select **Use alternate directory credentials**, enter
`DOMAIN\user` or `user@domain`, and enter the password in the masked field.
For a different forest, specify a server in that forest. The password is read
through WPF's `SecurePassword` property and cleared after each launch attempt.
Saved settings retain the choice to use alternate credentials, but omit the
account name and password. Re-enter them after loading settings. The copied
command uses `-Credential (Get-Credential)` and contains neither value.

Both the GUI and CLI credential option start a worker using Windows
`LOGON_NETCREDENTIALS_ONLY`. This applies the supplied credentials to network
access across AD and Group Policy collectors, including cmdlets without their
own Credential parameter. Local identity, local permissions, and local output
file ownership remain those of the signed-in account. Access to a UNC output
folder uses the worker's network credentials. Windows checks these credentials
when a network resource is accessed; successful process creation does not prove
the password or directory permissions are valid. Authentication failures remain
visible and never trigger a fallback to the original network credentials.

The password is passed to the Windows logon API through a temporary unmanaged
buffer that is zeroed immediately afterward. It is not placed in command-line
arguments, environment variables, JSON requests, saved settings, logs, or result
files. The selected account name and authentication mode are recorded for
troubleshooting; `RunAs` continues to describe the local Windows identity.
This credential mode requires Windows network logon support and a caller token
with a logon SID. The Windows API does not support LocalSystem callers.

The CLI returns the worker's serialized discovery result, preserving its data
properties. Ctrl+C stops the owned worker and its descendants. The supplied
PSCredential remains owned by the caller and can be reused by the caller.

Collection runs in an owned background process, keeping the window responsive.
**Live output** shows collector output and elapsed time. The **Results** tab
distinguishes Complete, Partial, Failed, and Stopped, displays inventory totals
and collection issues, and provides buttons for the run folder, discovery log,
execution status CSV, and discovery index when those files exist.

**Stop run** terminates the owned runner and its descendants. Completed exports
remain; interrupted datasets may leave unpublished `.partial` files. Closing a
window during collection asks whether to stop the run. A stopped run is never
reported as complete.

**Open launcher logs** opens the per-launch files under
`%TEMP%\ConsultingDiscoveryGui\<launch-id>`, including `console.log`, `errors.log`,
the submitted settings, and the result envelope. The on-screen console retains
a bounded amount of recent output; the log files retain the full output. Fatal
startup errors remain visible even if discovery never creates a run folder.
The GUI adds manual cancellation; it does not add automatic dataset timeouts.

Deploy the complete module folder, including `Gui`, `Private`, `Public`, and the
launcher scripts. The module import itself does not load WPF or open a window.

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

Native `DateTime` and `DateTimeOffset` values exported by `Export-AdCsvSafe`
use UTC ISO 8601 timestamps. Existing string values are preserved. This avoids
day/month ambiguity when exports are read on a machine with a different locale.
Dates without a timezone are interpreted in the runner's local timezone.

Assessment and migration analysis parse Boolean and integer fields explicitly
for consistent results before and after CSV import. Blank values remain unknown;
malformed nonblank Boolean, integer, or change-date values stop analysis with the
field name in the error. Historical date strings are parsed using invariant
culture; ambiguous exports from older versions may need their dates converted
to ISO 8601 using the original runner's locale.

`ObjectsRC4OnlyCount` counts explicit RC4 capability without AES. DES-only,
unset, and capability-only values such as `FAST_SUPPORTED` do not enter that
count. `Kerberos_NoAES` flags explicit DES or RC4 without AES, including when
the recorded risk label differs. High-cost site links use numeric cost greater
than 500. Disabled-account cleanup uses whole elapsed days and reports
`CleanupCandidate=Unknown` when `WhenChanged` is missing.

## Large Environments

SPN and SID-history inventory use server-side presence filters. The run retains
numeric forest totals and releases user/computer rows after their domain status
exports instead of keeping every domain's inventory until completion.

`Export-AdCsvSafe` serializes rows in batches of at most 256 to a unique
`.partial` file beside the destination. The completed file is published with a
same-directory rename or metadata-preserving replacement. A late invalid row or
write failure leaves an existing destination intact. Schema headers, UTC date
formatting, quoting, destination ACLs, and row order are preserved. Diagnostics
report staging progress every 10,000 rows; staging progress is not successful
publication. The writer closes between batches.

An interrupted producer or terminated PowerShell process may leave an unpublished
`.partial` file. These files are excluded from CSV manifests and the discovery
index. After the run has stopped, they can be removed; they are not completed
discovery datasets. Atomic replacement requires filesystem support and permission
to preserve the destination's metadata. If replacement fails, the exporter
reports the error rather than falling back to deleting the destination.

Automatic DC selection excludes known read-only candidates and checks ADWS TCP
9389 with a 1,500 ms per-probe limit and a 10,000 ms total connectivity-probe
budget. Internal `Get-AdWritableDc` parameters `TimeoutMs` and `ProbeBudgetMs`
can adjust those limits. DC enumeration and subsequent authenticated AD/GPO
operations still use their native timeouts. A domain FQDN fallback retains the
existing explicit-domain targeting and naming-context validation.

These changes reduce avoidable work and bound connectivity probing. They do not
yet enforce a hard deadline on an entire dataset or run; configurable paging,
classified retries, and supervised operation deadlines remain separate work.

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
& .\Tests\DiscoveryAssessment.Tests.ps1
& .\Tests\DiscoveryPerformance.Tests.ps1
& .\Tests\DiscoveryGui.Tests.ps1
& .\Tests\DiscoveryCredentials.Tests.ps1
```

The contract suite checks all declared exports and registered schema shapes,
then exercises collectors, CSV round trips, and consumers with empty, single-row,
and multi-row mocked directory datasets. Run the checks in both Windows
PowerShell 5.1 and PowerShell 7 when changing module contracts.
The assessment suite verifies expected counts and flags before and after CSV
import, threshold boundaries, missing values, and date exports under US, UK,
and French locales.

For a larger local CSV exercise (no AD queries):

```powershell
& .\Tests\DiscoveryPerformance.Tests.ps1 -RowCounts 10000,100000,500000
```

The performance suite verifies bounded buffering, atomic publication and ACL
preservation, interrupted producers, filtered query contracts, and connection
probe limits. Its timing and process peak-memory figures describe local CSV
serialization, not customer AD throughput.

The GUI suite checks every parameter against command metadata, saved settings,
literal argument handling, Complete/Partial/Failed/Stopped outcomes, output
capture, process ownership, and final window state using mocked collectors in
both available engines. For an interactive mock window with no AD queries:

```powershell
& .\Tests\DiscoveryGui.Tests.ps1 -ShowMockGui
```

The credential suite uses synthetic credentials with a local fake collector. It
checks the Windows network logon identifier, unchanged local identity, password
clearing, password non-persistence, CLI delegation, and cancellation. Live AD/GPO
authentication and target permissions require validation in the customer domain.

Windows behavior: [CreateProcessWithLogonW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createprocesswithlogonw).
