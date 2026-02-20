# M365 Discovery Collector Customer Run Guide

## Purpose
This guide is for customer-operated collection where consultants do not run privileged discovery directly.

It defines:
- Who does setup vs who runs discovery
- Exact commands for each role
- What artifacts to hand back
- Quick troubleshooting

## Role Boundaries
- `Bootstrap Admin` role:
  - Creates/updates app registration
  - Adds Graph permissions
  - Grants admin consent
  - Does not run regular discovery jobs
- `Operator` role:
  - Uses approved app config
  - Runs self-check, preflight, and discovery
  - Does not change app registration or consent

CLI enforcement:
- Runtime/preflight path requires `--role operator`
- `--role bootstrap-admin` is blocked in runtime flow

## Prerequisites
- Windows with `PowerShell 7.x` and `.NET SDK 8.x`
- Network access to Microsoft Graph endpoints
- Repo or packaged drop containing:
  - `M365.Discovery.Collector/Collector.Console`
  - `M365.Discovery.Collector/Collector.App` (optional GUI path)
  - `M365.Discovery.Collector/scripts/Setup-M365DiscoveryApp.ps1`
  - `M365.Discovery.Collector/scripts/run-collector.ps1`
  - `M365.Discovery.Collector/scripts/collector-config.template.json`

## Bootstrap Admin Procedure (one-time per tenant/app update)
1. Open PowerShell 7.
2. Run app setup:

```powershell
pwsh .\M365.Discovery.Collector\scripts\Setup-M365DiscoveryApp.ps1 `
  -TenantId <tenant-guid-or-domain> `
  -CreateSelfSignedCertificate `
  -OutputConfigPath .\m365-discovery-auth-config.json
```

3. Grant admin consent using the URL printed by the script.
4. Deliver these to operator:
- Client ID
- Tenant ID
- Certificate thumbprint (or approved certificate details)
- Config file (or values to populate config file)

## Operator Procedure (every run)
1. Use approved config file (example path):
- `%APPDATA%\M365DiscoveryCollector\config.json`

2. Run self-check and preflight first:

```powershell
pwsh .\M365.Discovery.Collector\scripts\run-collector.ps1 `
  -Role operator `
  -ConfigPath "$env:APPDATA\M365DiscoveryCollector\config.json" `
  -Workloads default `
  -SelfCheck `
  -PreflightOnly
```

3. Run full collection:

```powershell
pwsh .\M365.Discovery.Collector\scripts\run-collector.ps1 `
  -Role operator `
  -ConfigPath "$env:APPDATA\M365DiscoveryCollector\config.json" `
  -Workloads all `
  -SelfCheck
```

4. Optional targeted workload run:

```powershell
pwsh .\M365.Discovery.Collector\scripts\run-collector.ps1 `
  -Role operator `
  -ConfigPath "$env:APPDATA\M365DiscoveryCollector\config.json" `
  -Workloads "entra.roles,entra.conditionalAccess,entra.authMethods,hybrid.aadConnectConfig" `
  -SelfCheck
```

## Output Artifacts to Return
From the run folder:
- `RunMetadata.json`
- `Summary.csv`
- `Discovery_AccessGaps.csv`
- `RiskAnalysis.csv`
- All workload CSV outputs
- Runner log from output root: `Discovery_*.log`

## Common Issues
1. `Role boundary` error:
- Use `-Role operator` for runtime runs.

2. Config not found:
- Use explicit `-ConfigPath`.
- CLI also falls back to `%APPDATA%\M365DiscoveryCollector\config.json` when `collector-config.json` is missing.

3. Permission/consent failures:
- Re-run bootstrap permission + consent flow.
- Re-authenticate and rerun preflight.

4. App-only token missing roles:
- Confirm Graph application permissions were added and admin consented.
- Confirm certificate thumbprint/subject matches app credential.

5. Output write failures:
- Change `-OutputRoot` to a writable folder.

## Minimum Handoff Checklist
- App registration created and documented
- Admin consent granted
- Config validated by operator self-check
- Preflight report clean (or known access gaps documented)
- Discovery outputs and logs delivered
