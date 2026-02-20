# M365 Discovery Collector

This solution supports a **customer-run** M365/Entra discovery collector with GUI and CLI entry points.

## CI Status
[![M365 Collector CI](https://github.com/Lagana-Consulting/Consulting.Toolkit/actions/workflows/m365-collector-ci.yml/badge.svg?branch=main)](https://github.com/Lagana-Consulting/Consulting.Toolkit/actions/workflows/m365-collector-ci.yml)

- Workflow: `M365 Collector CI`
- Scope: CLI smoke checks + release package artifact validation

## What works right now
- WPF desktop GUI with workload selection and preflight checks
- Headless CLI runner (`Collector.Console`) for customer-operated runs
- Output pipeline with CSV exports, `RunMetadata.json`, `Summary.csv`, `Discovery_AccessGaps.csv`, `RiskAnalysis.csv`

## CLI usage
Build:
`dotnet build M365.Discovery.Collector/M365.Discovery.Collector.sln`

List workload keys:
`dotnet run --project M365.Discovery.Collector/Collector.Console/Collector.Console.csproj -- --list-workloads`

Role boundary (explicit operator mode):
`dotnet run --project M365.Discovery.Collector/Collector.Console/Collector.Console.csproj -- --role operator --config collector-config.json --workloads default --preflight-only`

Self-check (no auth call; validates role/config/workloads/output access):
`dotnet run --project M365.Discovery.Collector/Collector.Console/Collector.Console.csproj -- --role operator --config collector-config.json --workloads default --output-root .\CollectorOutput --self-check`

Preflight only (app-only with certificate thumbprint):
`dotnet run --project M365.Discovery.Collector/Collector.Console/Collector.Console.csproj -- --mode app-only --client-id <appId> --tenant-id <tenantId> --cert-thumbprint <thumbprint> --workloads default --preflight-only`

Run selected workloads (comma-separated keys):
`dotnet run --project M365.Discovery.Collector/Collector.Console/Collector.Console.csproj -- --mode app-only --client-id <appId> --tenant-id <tenantId> --cert-thumbprint <thumbprint> --workloads entra.roles,entra.conditionalAccess,entra.authMethods,hybrid.aadConnectConfig`

Use config file (defaults to `collector-config.json` if `--config` omitted):
`dotnet run --project M365.Discovery.Collector/Collector.Console/Collector.Console.csproj -- --config collector-config.json --workloads all`

## Customer runner script
Template config:
`M365.Discovery.Collector/scripts/collector-config.template.json`

Wrapper script (build + run + log capture):
`pwsh M365.Discovery.Collector/scripts/run-collector.ps1 -PreflightOnly`

Examples:
`pwsh M365.Discovery.Collector/scripts/run-collector.ps1 -ConfigPath "$env:APPDATA/M365DiscoveryCollector/config.json" -Workloads default -PreflightOnly`

`pwsh M365.Discovery.Collector/scripts/run-collector.ps1 -ConfigPath "$env:APPDATA/M365DiscoveryCollector/config.json" -Workloads all`

`pwsh M365.Discovery.Collector/scripts/run-collector.ps1 -ConfigPath "$env:APPDATA/M365DiscoveryCollector/config.json" -Workloads default -SelfCheck -PreflightOnly`

## Customer packaging
Build a customer-ready release zip (binaries + scripts + run guide):
`pwsh M365.Discovery.Collector/scripts/Build-M365CollectorRelease.ps1`

Optional (skip GUI publish):
`pwsh M365.Discovery.Collector/scripts/Build-M365CollectorRelease.ps1 -SkipGui`

## Smoke checks
Run local CLI smoke checks (same assertions used in CI):
`pwsh M365.Discovery.Collector/scripts/Test-M365CollectorSmoke.ps1`

## Output
Both GUI and CLI write outputs under:
`<OutputFolder>\<RunName>\`

## Notes
- Target frameworks:
  - Collector.Console: net8.0
  - Collector.App: net8.0-windows (WPF)
  - Other projects: net8.0
- This solution is designed to *degrade gracefully* when permissions are limited.
- CLI role boundaries: run/preflight is `--role operator` (default). `--role bootstrap-admin` is intentionally blocked in the runtime CLI path.

