# AD Discovery Customer Run Guide

## Purpose
This guide documents how customers run `Consulting.Toolkit.Discovery` safely and consistently without requiring consultant-run privileged sessions.

## Scope
- Active Directory discovery only
- Script/module-based collection
- Structured CSV export + manifest output

## Runtime and Host Requirements
- Windows host (server or workstation with AD tools)
- Windows PowerShell 5.1 (recommended runtime)
- ActiveDirectory module (RSAT AD DS tools)
- GroupPolicy module recommended when using `-IncludeSecurity`

## Package Contents (Release Bundle)
- `module/Consulting.Toolkit.Discovery/`
- `scripts/run-ad-discovery.ps1`
- `scripts/Test-ADDiscoverySmoke.ps1`
- `scripts/ad-discovery-run-settings.template.json`

## Step 1: Validate Host Readiness
Run smoke checks before first run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-ADDiscoverySmoke.ps1 -IncludeSecurity
```

If smoke check returns non-zero, fix failures before proceeding.

## Step 2: Optional Settings File
Create a run settings file from template:

```powershell
Copy-Item .\scripts\ad-discovery-run-settings.template.json .\ad-discovery.settings.json
```

Edit values:
- `Environment`
- `OutputRoot`
- `CustomerName`
- `Server` (optional DC)
- `IncludeSecurity`

## Step 3: Preflight Only
Validate module import, AD cmdlets, and output path without running discovery:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-ad-discovery.ps1 -ConfigPath .\ad-discovery.settings.json -PreflightOnly
```

## Step 4: Run Discovery
Run full AD discovery:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-ad-discovery.ps1 -ConfigPath .\ad-discovery.settings.json
```

Or run directly with parameters:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-ad-discovery.ps1 -Environment Source -OutputRoot C:\Discovery -IncludeSecurity
```

## Expected Output Artifacts
From returned `RunRoot`:
- `00_schemas\*`
- `10_forest\*`
- `20_domains\*`
- `90_logs\*`
- `99_manifest\Discovery.Index.json`

From runner output root:
- `ad-discovery-runner-<timestamp>.log`

## Common Issues
1. `Get-ADDomain missing`:
- Install RSAT AD DS tools / ActiveDirectory module.

2. GroupPolicy warnings with `-IncludeSecurity`:
- Install RSAT Group Policy tools (`Get-GPO`).

3. Non-writable output path:
- Change `-OutputRoot` to a writable folder.

4. Running in PowerShell 7:
- Supported in some environments, but 5.1 is recommended for AD module compatibility.

## Minimal Handoff Checklist
- Smoke checks pass (or warnings documented)
- Preflight-only run succeeds
- Full run succeeds
- `RunRoot` + runner log collected and delivered
