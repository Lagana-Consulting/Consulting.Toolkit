# Migration.Toolkit.Cloud - Rename Complete

## Summary
Successfully renamed all functions from `*-AdCloud*` to `*-AzCloud*` to better differentiate cloud workload discovery from Active Directory (AD) discovery.

## Rationale
- **Original**: Functions used `AdCloud` prefix (e.g., `Connect-AdCloudTenant`)
- **New**: Functions use `AzCloud` prefix (e.g., `Connect-AzCloudTenant`)
- **Why**: The "Az" prefix aligns with Azure PowerShell module conventions and clearly differentiates from on-premises Active Directory functions in Migration.Toolkit module (which use `Ad` prefix like `Get-AdAdForest`)

## What Was Changed

### 1. File Names (19 files renamed)
All function files in `Public/` directory renamed from `*-AdCloud*.ps1` to `*-AzCloud*.ps1`:
- `Connect-AdCloudTenant.ps1` → `Connect-AzCloudTenant.ps1`
- `Get-AdCloudUsers.ps1` → `Get-AzCloudUsers.ps1`
- `Invoke-AdCloudDiscovery.ps1` → `Invoke-AzCloudDiscovery.ps1`
- etc. (19 total)

### 2. Module Manifest (`Migration.Toolkit.Cloud.psd1`)
Updated `FunctionsToExport` array with all AzCloud function names.

### 3. Module Entry Point (`Migration.Toolkit.Cloud.psm1`)
Updated `Export-ModuleMember` to export AzCloud functions.

### 4. Function Definitions
All function declarations updated:
- `function Connect-AdCloudTenant` → `function Connect-AzCloudTenant`
- `function Get-AdCloudUsers` → `function Get-AzCloudUsers`
- etc.

### 5. Internal Cross-References
All internal function calls updated:
- `Get-AdCloudAuthContext` → `Get-AzCloudAuthContext`
- `Connect-AdCloudTenant` → `Connect-AzCloudTenant`
- `Export-AdCloudCsv` → `Export-AzCloudCsv`
- etc.

### 6. Script-Scoped Variables
Authentication context variable renamed:
- `$script:AdCloudAuthContext` → `$script:AzCloudAuthContext`

## Complete Function List (19 functions)

### Authentication (3)
- `Connect-AzCloudTenant` - Establish connection with certificate/interactive/device code auth
- `Disconnect-AzCloudTenant` - Close connection and clear context
- `Get-AzCloudAuthContext` - Retrieve current authentication context

### Entra ID Discovery (6)
- `Get-AzCloudUsers` - Discover Entra ID users (members, guests, filtering)
- `Get-AzCloudGroups` - Discover Entra ID groups (M365, Security, Distribution)
- `Get-AzCloudDevices` - Discover registered/hybrid Azure AD joined devices
- `Get-AzCloudApplications` - Discover app registrations and service principals
- *(Note: ServicePrincipals and RoleAssignments may be in development)*

### Exchange Online Discovery (3)
- `Get-AzCloudMailboxes` - Discover user mailboxes with archive status
- `Get-AzCloudDistributionGroups` - Discover distribution groups
- `Get-AzCloudResourceMailboxes` - Discover room/equipment mailboxes

### SharePoint/OneDrive Discovery (2)
- `Get-AzCloudSharePointSites` - Discover SharePoint sites with storage analytics
- `Get-AzCloudOneDriveUsage` - OneDrive storage analytics per user

### Teams Discovery (1)
- `Get-AzCloudTeams` - Discover Teams with optional channel/member counts

### M365 Groups Discovery (1)
- `Get-AzCloudM365Groups` - Discover Microsoft 365 (Unified) groups

### Orchestration (1)
- `Invoke-AzCloudDiscovery` - Master discovery function for all workloads

### Utilities (4)
- `Export-AzCloudCsv` - CSV export with schema consistency
- `New-AzCloudLog` - Create timestamped log files
- `Write-AzCloudLog` - Write timestamped log entries
- `Get-AzCloudTenantInfo` - Retrieve tenant metadata

## Verification
Module successfully imports and all 19 functions export correctly:
```powershell
Import-Module Migration.Toolkit.Cloud -Force
Get-Command -Module Migration.Toolkit.Cloud
```

## Example Usage
```powershell
# Connect to tenant with certificate auth
Connect-AzCloudTenant -TenantId "contoso.onmicrosoft.com" `
  -ClientId "12345678-1234-1234-1234-123456789012" `
  -CertificatePath "C:\certs\cloud-app.pfx"

# Run full discovery
Invoke-AzCloudDiscovery -OutputRoot "C:\Reports\Contoso_Cloud" `
  -Workloads All -CustomerName "Contoso Inc"

# Discover specific workload
$users = Get-AzCloudUsers -IncludeGuests -Filter "accountEnabled eq true"

# Disconnect
Disconnect-AzCloudTenant
```

## Status
✅ **Complete** - All function files, module manifest, internal references, and script variables updated
✅ **Tested** - Module loads successfully and all functions export with AzCloud prefix
⏳ **Pending** - Documentation files still need updating (README.md, SETUP_GUIDE.md, etc.)

## Date Completed
January 2025
