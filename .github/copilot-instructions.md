# Migration Toolkit - AI Coding Agent Instructions

## Project Overview
**Migration.Toolkit** is a PowerShell module providing AD discovery, assessment, and migration planning utilities. It emphasizes Quest migration tool integration, secure logging, and comprehensive AD analysis.

## Architecture & Organization

### Module Structure
This repository contains two PowerShell modules:

#### Migration.Toolkit (src/Migration.Toolkit/)
- **Migration.Toolkit.psm1**: Root module entry point that dot-sources Private/ then Public/ functions
- **Migration.Toolkit.psd1**: Module manifest (v0.1.1, PowerShell 5.1+)
- **Public/**: User-facing functions (~62 exported cmdlets). Organized by domain: logging, auth, forest/domain queries, assessment, risk analysis
- **Private/**: Helper functions. Prefixed `Get-Ad*` or `Convert-Ad*`. Examples: `Get-AdTimestamp`, `Resolve-AdPath`, `Get-AdGroupMembersRecursive`
- **Focus**: Server-side AD discovery and assessment (compatible with Quest migration tools)

#### Migration.Toolkit.Analysis (src/Migration.Toolkit.Analysis/)
- **Migration.Toolkit.Analysis.psd1**: Module manifest (PowerShell 7+ required)
- **Public/**: Client-side analysis and reporting functions
- **Focus**: Offline analysis, HTML report generation, cross-forest duplicate detection

### Function Naming Convention
All functions use `*-Ad*` prefix: `Verb-AdNoun`. Examples:
- `Get-AdAdForest`, `New-AdLog`, `Export-AdCsvSafe`
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
- **ActiveDirectory module** (RSAT): Required for all AD queries (Get-AdAd* family)
- **Microsoft Graph SDK**: Used by `Connect-AdGraph`, `Confirm-AdTenant` for tenant-safe auth
- **Pester 5+**: Testing framework in tests/Lagana.Consulting.Toolkit.Tests.ps1

### Tenant Safety Pattern
`Confirm-AdTenant` validates Graph connection before operations to prevent cross-tenant accidents. Always call this before Graph mutations.

### CSV Export Pattern
`Export-AdCsvSafe` enforces column ordering via optional `SchemaName` parameter (linked to `Get-AdSchemaDefinitions`). Use over native `Export-Csv` to avoid schema drift in reporting pipelines.

## Development Workflows

### Module Loading (Dev)
From repo root: `Import-Module "$PWD\src\Migration.Toolkit" -Force`
Always use `-Force` during iteration to reload updated functions.

### Testing
```powershell
Invoke-Pester tests/Lagana.Consulting.Toolkit.Tests.ps1
```
Current tests verify exported command names. Expand with functional tests for new critical features (e.g., AD queries, CSV validation).

### Code Quality
- **PSScriptAnalyzer** configured via PSScriptAnalyzerSettings.psd1 (Severity: Error, Warning)
- Run before committing: `Invoke-ScriptAnalyzer -Path src/ -Settings src/Migration.Toolkit/PSScriptAnalyzerSettings.psd1`
- ExcludePath allows client scripts/ to use looser patterns; core module stays strict

### Build/Deployment
No formal build system yet. Module is directly importable from src/. CI likely uses GitHub Actions (workflows/ exists but empty).

## Patterns & Conventions

### Private Helper Pattern
Private functions handle cross-cutting concerns:
- `Get-AdTimestamp`: Timestamp generation (File/Iso formats)
- `Resolve-AdPath`: Safe path resolution with environment expansion
- `Get-AdGroupMembersRecursive`: Recursive AD group expansion (used by privilege queries)

### Logging Pattern
`New-AdLog` creates log file (returns path). `Write-AdLog` appends timestamped entries. Example:
```powershell
$log = New-AdLog -Folder "C:\logs" -Prefix "report"
Write-AdLog -Path $log -Message "Starting AD enumeration"
```

### AD Query Pattern
Most AD functions accept optional `-Server` (DC/GC override) and `-ForestName` parameters for locked-down networks:
```powershell
Get-AdAdDomains -Server "gc.corp.local"
```

### Pipeline Input Pattern
`Export-AdCsvSafe` and similar data consumers use `[Parameter(ValueFromPipeline)]` for `begin/process/end` blocks to handle streaming input efficiently.

## Common Pitfalls

- **Missing RSAT AD tools**: Many functions throw if ActiveDirectory module unavailable. Installation is user responsibility.
- **Path resolution**: Use `Resolve-AdPath` (not raw paths) to handle UNC, relative, and environment variable paths safely.
- **Schema-less CSV**: Don't use raw `Export-Csv` for reporting—use `Export-AdCsvSafe -SchemaName` to enforce column consistency across runs.
- **Cross-tenant operations**: Always call `Confirm-AdTenant` before Graph mutations.

## When Adding New Functions

1. Decide Public (exported in .psm1's Export-ModuleMember) vs. Private
2. Follow `*-AdNoun` naming (e.g., `Get-AdAdServers`)
3. Use `[CmdletBinding()]` and parameter validation (`[Parameter(Mandatory)]`, `[ValidateSet(...)]`)
4. Add error context (target name, error message) in throw statements
5. Update Migration.Toolkit.psd1 FunctionsToExport if public
6. Group in .psm1 comments by domain (e.g., "# Forest + domains")
7. Add Pester tests verifying export and core behavior

## File References
- Core: [src/Migration.Toolkit/Migration.Toolkit.psm1](../src/Migration.Toolkit/Migration.Toolkit.psm1)
- Config: [PSScriptAnalyzerSettings.psd1](../src/Migration.Toolkit/PSScriptAnalyzerSettings.psd1)
- Tests: [tests/Lagana.Consulting.Toolkit.Tests.ps1](../tests/Lagana.Consulting.Toolkit.Tests.ps1)
- Example: [Public/Get-AdAdForest.ps1](../src/Migration.Toolkit/Public/Get-AdAdForest.ps1)
