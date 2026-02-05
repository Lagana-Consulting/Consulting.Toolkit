# M365 Discovery Collector (Starter)

This is a Visual Studio starter solution for a **customer-run** M365/Entra discovery collector.

## What works right now
- WPF desktop GUI with workload checkboxes (Entra, OneDrive, SharePoint, Teams)
- Preflight stub (shows how the UI will present Available/Partial/Blocked)
- Run Selected generates placeholder CSVs + RunMetadata.json + Summary.csv + AccessGaps.csv

## What you wire up next
- Add MSAL interactive sign-in (Collector.Graph)
- Implement endpoint probes in PreflightService
- Replace SampleDataFactory + CsvExportService usage with real collectors:
  - Entra: users, groups, apps, service principals, directory roles
  - Reports: OneDrive/SPO/Teams usage reports (where permitted)
- Expand AccessGaps.csv generation based on 403/permission failures

## Output
The app writes all outputs under:
`<OutputFolder>\<RunName>\`

## Notes
- Target frameworks:
  - Collector.App: net8.0-windows (WPF)
  - Other projects: net8.0
- This solution is designed to *degrade gracefully* when permissions are limited.

