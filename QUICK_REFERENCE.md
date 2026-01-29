# Cloud Discovery - Quick Reference

## Module Status
✅ **READY FOR PRODUCTION USE**

- 19 functions exported
- All syntax validated
- Graceful error handling implemented
- Safe count aggregation pattern applied

## Quick Start

### 1. Load the Module
```powershell
Import-Module 'C:\Users\PLagana\OneDrive - Quest\Documents\GitHub\Migration.Toolkit\src\Migration.Toolkit.Cloud' -Force
```

### 2. Connect to Your Tenant
```powershell
# Using certificate (recommended)
Connect-AzCloudTenant -TenantId "your-tenant-id" `
  -ClientId "app-id" `
  -CertificatePath "C:\certs\cert.pfx" `
  -CertificatePassword (ConvertTo-SecureString "password" -AsPlainText -Force)

# Using device code (interactive)
Connect-AzCloudTenant -TenantId "your-tenant-id" `
  -ClientId "app-id" `
  -AuthType DeviceCode
```

### 3. Run Discovery
```powershell
# Discover all workloads
Invoke-AzCloudDiscovery -OutputRoot "C:\Reports\Cloud_Discovery" `
  -Workloads All `
  -CustomerName "My Organization" `
  -ExportCsv `
  -GenerateReport

# Discover specific workloads only
Invoke-AzCloudDiscovery -OutputRoot "C:\Reports\Teams_Only" `
  -Workloads Teams `
  -CustomerName "My Organization"
```

### 4. Review Results
```
C:\Reports\Cloud_Discovery\
├── 10_entra/
│   ├── Users.csv
│   ├── Groups.csv
│   ├── Devices.csv
│   └── Applications.csv
├── 20_exchange/
│   ├── Mailboxes.csv
│   ├── DistributionGroups.csv
│   └── ResourceMailboxes.csv
├── 30_sharepoint/
│   ├── Sites.csv
│   └── OneDriveUsage.csv
├── 40_teams/
│   └── Teams.csv
├── 50_m365groups/
│   └── M365Groups.csv
├── 99_reports/
│   └── Assessment_Report_*.html
└── logs/
    └── discovery_*.log
```

## What Changed

### Distribution Groups
- **Before**: Threw error "Get-DistributionGroup is not recognized"
- **After**: Returns empty array with warning (graceful skip)

### Count Aggregation
- **Before**: Error "The property 'Count' cannot be found"
- **After**: Safe counting using Measure-Object

### Result
- Discovery completes even if some workloads fail
- Gets partial results instead of no results
- Never crashes on MS-Graph SDK issues

## Discovery Functions (19 total)

### Authentication (2)
- `Connect-AzCloudTenant` - Connect to tenant
- `Disconnect-AzCloudTenant` - Cleanup

### Entra ID (4)
- `Get-AzCloudUsers` - Entra users
- `Get-AzCloudGroups` - Entra groups
- `Get-AzCloudDevices` - Azure AD devices
- `Get-AzCloudApplications` - App registrations

### Exchange (3)
- `Get-AzCloudMailboxes` - Exchange mailboxes
- `Get-AzCloudDistributionGroups` - Dist groups (Graph unavailable)
- `Get-AzCloudResourceMailboxes` - Resource mailboxes

### SharePoint (2)
- `Get-AzCloudSharePointSites` - SharePoint sites
- `Get-AzCloudOneDriveUsage` - OneDrive per user

### Teams (1)
- `Get-AzCloudTeams` - Teams (fully functional)

### M365 Groups (1)
- `Get-AzCloudM365Groups` - M365 groups

### Orchestration (4)
- `Invoke-AzCloudDiscovery` - Main discovery orchestrator
- `Export-AzCloudCsv` - CSV export helper
- `Get-AzCloudAuthContext` - Authentication state
- `Get-AzCloudTenantInfo` - Tenant metadata

### Utilities (2)
- `New-AzCloudLog` - Create log file
- `Write-AzCloudLog` - Write log entries

## Error Handling

All functions handle errors gracefully:
- ✅ Returns empty array if discovery fails
- ✅ Logs warning instead of throwing
- ✅ Orchestrator continues with next workload
- ✅ Discovery completes with partial results

Example output with errors:
```
Entra ID: 150 users, 45 groups, 28 devices, 12 applications
Exchange: 0 mailboxes, 0 dist groups, 0 resources (requires EXO connection)
SharePoint: 8 sites, 145 OneDrive users
Teams: 5 teams
M365 Groups: 23 groups

Total: 416 records discovered
```

## Troubleshooting

### "Not connected to cloud tenant"
```powershell
# Run connect first
Connect-AzCloudTenant -TenantId "your-id" -ClientId "app-id"
```

### "Module not found"
```powershell
# Make sure path is correct
Import-Module 'C:\path\to\Migration.Toolkit.Cloud' -Force
```

### No results for a workload
- ✓ Normal - that workload may not have data
- ✓ Check logs for warnings
- ✓ Use `Connect-ExchangeOnline` for distribution groups

### Discovery taking too long
- ✓ Large tenants (>1000 users) may take 5-10 minutes
- ✓ Network latency affects speed
- ✓ Discover individual workloads separately for testing

## Quick Validation

```powershell
# Test module loads
Import-Module 'C:\Users\PLagana\OneDrive - Quest\Documents\GitHub\Migration.Toolkit\src\Migration.Toolkit.Cloud' -Force
Get-Command -Module Migration.Toolkit.Cloud | Measure-Object  # Should show 19

# Test individual functions work
Get-AzCloudUsers -ErrorAction SilentlyContinue | Measure-Object
Get-AzCloudTeams -ErrorAction SilentlyContinue | Measure-Object
Get-AzCloudDistributionGroups  # Should warn about EXO requirement

# Test count aggregation
$arr = @(1,2,3)
if ($arr) { ($arr | Measure-Object).Count } else { 0 }  # Returns 3
```

## Key Improvements

1. **Resilient to SDK Versions**
   - Doesn't crash on SDK compatibility issues
   - Gracefully skips unavailable features

2. **Handles All Array Sizes**
   - Empty results (0 items)
   - Single item results
   - Multiple item results

3. **Clear Error Messages**
   - Warnings instead of exceptions
   - User knows what worked and what didn't

4. **Partial Success**
   - Some workloads succeed while others fail
   - Useful for multi-workload discovery in complex environments

## Files for Reference

- **Module**: `src/Migration.Toolkit.Cloud/Migration.Toolkit.Cloud.psm1`
- **Manifest**: `src/Migration.Toolkit.Cloud/Migration.Toolkit.Cloud.psd1`
- **Discovery**: `src/Migration.Toolkit.Cloud/Public/Invoke-AzCloudDiscovery.ps1`
- **Dist Groups Fix**: `src/Migration.Toolkit.Cloud/Public/Get-AzCloudDistributionGroups.ps1`
- **Full Docs**: `RESILIENCE_FIXES_SUMMARY.md`
- **Detailed Docs**: `RESILIENCE_FIXES_APPLIED.md`
- **Validation**: `Test-CloudDiscoveryResilience.ps1`

---
✅ Ready to use. All resilience improvements applied and tested.
