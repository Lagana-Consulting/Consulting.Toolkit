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
- `Export-AdCsvSafe`
- `Export-AdSchemas`

Most `Get-Ad*` functions are lower-level collectors used by
`Invoke-AdDiscoveryExport`.

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

## Troubleshooting

If module import fails, confirm the path points to the `.psd1` file:

```

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

If some datasets are empty or missing, review the collector log in `90_logs` and
confirm the running account has read access for that data area.
