# Lagana Consulting Toolkit - AI Coding Agent Instructions

## Project Overview
**lc-toolkit** is a PowerShell module providing reusable automation utilities for AD/Microsoft Graph consulting engagements. It emphasizes tenant-safe operations, secure logging, and Windows identity querying (AD forest/domain/replication/GPO/ADMT workflows).

## Architecture & Organization

### Module Structure (src/Lagana.Consulting.Toolkit/)
- **Lagana.Consulting.Toolkit.psm1**: Root module entry point that dot-sources Private/ then Public/ functions, then exports public API via `Export-ModuleMember`
- **Lagana.Consulting.Toolkit.psd1**: Module manifest (v0.1.0, PowerShell 5.1+, GUID: 8593c972-06bc-4b0a-a680-0a61fcda0c3e)
- **Public/**: User-facing functions (~43 exported cmdlets). Organized by domain: logging, auth, forest/domain queries, ADMT operations, risk assessment
- **Private/**: Helper functions (~18). Prefixed `Get-Lc*` or `Convert-Lc*`. Examples: `Get-LcTimestamp`, `Resolve-LcPath`, `Get-LcGroupMembersRecursive`

### Function Naming Convention
All functions use `*-Lc*` prefix: `Verb-LcNoun`. Examples:
- `Get-LcAdForest`, `New-LcLog`, `Export-LcCsvSafe`
- Maintains consistency and reduces namespace pollution

### Error Handling Pattern
Functions validate prerequisites early (e.g., `Get-ADForest` availability) and throw descriptive errors:
```powershell
if (-not (Get-Command Get-ADForest -ErrorAction SilentlyContinue)) {
  throw "ActiveDirectory module not available. Install RSAT AD tools."
}
```

## Key Integration Points

### External Dependencies
- **ActiveDirectory module** (RSAT): Required for all AD queries (Get-LcAd* family)
- **Microsoft Graph SDK**: Used by `Connect-LcGraph`, `Confirm-LcTenant` for tenant-safe auth
- **Pester 5+**: Testing framework in tests/Lagana.Consulting.Toolkit.Tests.ps1

### Tenant Safety Pattern
`Confirm-LcTenant` validates Graph connection before operations to prevent cross-tenant accidents. Always call this before Graph mutations.

### CSV Export Pattern
`Export-LcCsvSafe` enforces column ordering via optional `SchemaName` parameter (linked to `Get-LcSchemaDefinitions`). Use over native `Export-Csv` to avoid schema drift in reporting pipelines.

## Development Workflows

### Module Loading (Dev)
From repo root: `Import-Module "$PWD\src\Lagana.Consulting.Toolkit" -Force`
Always use `-Force` during iteration to reload updated functions.

### Testing
```powershell
Invoke-Pester tests/Lagana.Consulting.Toolkit.Tests.ps1
```
Current tests verify exported command names. Expand with functional tests for new critical features (e.g., AD queries, CSV validation).

### Code Quality
- **PSScriptAnalyzer** configured via PSScriptAnalyzerSettings.psd1 (Severity: Error, Warning)
- Run before committing: `Invoke-ScriptAnalyzer -Path src/ -Settings src/Lagana.Consulting.Toolkit/PSScriptAnalyzerSettings.psd1`
- ExcludePath allows client scripts/ to use looser patterns; core module stays strict

### Build/Deployment
No formal build system yet. Module is directly importable from src/. CI likely uses GitHub Actions (workflows/ exists but empty).

## Patterns & Conventions

### Private Helper Pattern
Private functions handle cross-cutting concerns:
- `Get-LcTimestamp`: Timestamp generation (File/Iso formats)
- `Resolve-LcPath`: Safe path resolution with environment expansion
- `Get-LcGroupMembersRecursive`: Recursive AD group expansion (used by privilege queries)

### Logging Pattern
`New-LcLog` creates log file (returns path). `Write-LcLog` appends timestamped entries. Example:
```powershell
$log = New-LcLog -Folder "C:\logs" -Prefix "report"
Write-LcLog -Path $log -Message "Starting AD enumeration"
```

### AD Query Pattern
Most AD functions accept optional `-Server` (DC/GC override) and `-ForestName` parameters for locked-down networks:
```powershell
Get-LcAdDomains -Server "gc.corp.local"
```

### Pipeline Input Pattern
`Export-LcCsvSafe` and similar data consumers use `[Parameter(ValueFromPipeline)]` for `begin/process/end` blocks to handle streaming input efficiently.

## Common Pitfalls

- **Missing RSAT AD tools**: Many functions throw if ActiveDirectory module unavailable. Installation is user responsibility.
- **Path resolution**: Use `Resolve-LcPath` (not raw paths) to handle UNC, relative, and environment variable paths safely.
- **Schema-less CSV**: Don't use raw `Export-Csv` for reporting—use `Export-LcCsvSafe -SchemaName` to enforce column consistency across runs.
- **Cross-tenant operations**: Always call `Confirm-LcTenant` before Graph mutations.

## When Adding New Functions

1. Decide Public (exported in .psm1's Export-ModuleMember) vs. Private
2. Follow `*-LcNoun` naming (e.g., `Get-LcAdServers`)
3. Use `[CmdletBinding()]` and parameter validation (`[Parameter(Mandatory)]`, `[ValidateSet(...)]`)
4. Add error context (target name, error message) in throw statements
5. Update Lagana.Consulting.Toolkit.psd1 FunctionsToExport if public
6. Group in .psm1 comments by domain (e.g., "# Forest + domains")
7. Add Pester tests verifying export and core behavior

## File References
- Core: [src/Lagana.Consulting.Toolkit/Lagana.Consulting.Toolkit.psm1](../src/Lagana.Consulting.Toolkit/Lagana.Consulting.Toolkit.psm1)
- Config: [PSScriptAnalyzerSettings.psd1](../src/Lagana.Consulting.Toolkit/PSScriptAnalyzerSettings.psd1)
- Tests: [tests/Lagana.Consulting.Toolkit.Tests.ps1](../tests/Lagana.Consulting.Toolkit.Tests.ps1)
- Example: [Public/Get-LcAdForest.ps1](../src/Lagana.Consulting.Toolkit/Public/Get-LcAdForest.ps1)
