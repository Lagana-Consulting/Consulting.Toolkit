# Migration.Toolkit.Cloud

Cloud workload discovery module for **Entra ID**, **Exchange Online**, **SharePoint**, **Teams**, and **Microsoft 365 Groups**. Designed for least-privilege access using certificate-based authentication via service principals.

## Features

### ✅ Complete Cloud Workload Discovery

- **Entra ID**: Users, groups, devices, applications, service principals, role assignments
- **Exchange Online**: Mailboxes, distribution groups, resource mailboxes (rooms/equipment), mailbox permissions
- **SharePoint & OneDrive**: Sites, site collections, OneDrive usage analytics
- **Teams**: Teams, channels, members, team settings
- **M365 Groups**: Microsoft 365 Groups with resource linkage (Teams, SharePoint, Yammer)

### ✅ Least-Privilege Security

- **Certificate-Based Auth**: Uses X.509 certificates for unattended authentication
- **Service Principal Support**: Create enterprise applications with minimal required permissions
- **No Shared Secrets**: Avoid client secrets; use certificates for security
- **Scoped Permissions**: Define exactly which API permissions are needed

### ✅ Flexible Authentication

- **Certificate Auth** (Recommended): Unattended, secure, suitable for scheduled tasks
- **Interactive Auth**: For testing and validation (user sign-in)
- **Device Code Flow**: Headless scenarios (sign-in on another device)

### ✅ Structured Output

- Organized workload directories (10_entra, 20_exchange, 30_sharepoint, 40_teams, 50_m365groups)
- CSV exports with consistent schema
- Timestamped logs and reports
- HTML summary reports (future expansion)

### ✅ Enterprise-Ready

- Large tenant support with pagination
- Error handling and recovery
- Comprehensive logging
- Configuration templates for deployment

## Quick Start

### 1. Install

```powershell
# Clone or download module
git clone https://github.com/lagana/Migration.Toolkit.git
cd Migration.Toolkit

# Import module
Import-Module .\src\Migration.Toolkit.Cloud -Force
```

### 2. Setup Service Principal and Certificate

**Option A: Automated Setup (Recommended)**

```powershell
# Requires Global Admin role
cd src\Migration.Toolkit.Cloud
.\Setup-CloudDiscoveryServicePrincipal.ps1 -TenantId "contoso.onmicrosoft.com"
```

This script will:
- Create Azure AD application registration
- Generate self-signed certificate
- Assign required API permissions
- Save configuration file

**Option B: Manual Setup**

Follow detailed instructions in [SETUP_GUIDE.md](SETUP_GUIDE.md).

### 3. Connect and Discover

```powershell
# Connect with certificate
Connect-AdCloudTenant `
  -TenantId "contoso.onmicrosoft.com" `
  -ClientId "12345678-1234-1234-1234-123456789012" `
  -CertificatePath "C:\certs\cloud-discovery.pfx" `
  -CertificatePassword (ConvertTo-SecureString "password" -AsPlainText -Force)

# Execute full discovery
$result = Invoke-AdCloudDiscovery `
  -OutputRoot "C:\Reports\CloudDiscovery_$(Get-Date -Format yyyyMMdd)" `
  -Workloads All `
  -CustomerName "Contoso Inc"

# View results
$result | Format-List
Get-ChildItem -Path $result.OutputPath -Recurse
```

## Module Functions

### Authentication

| Function | Purpose |
|----------|---------|
| `Connect-AdCloudTenant` | Establish authenticated connection to cloud tenant |
| `Disconnect-AdCloudTenant` | Close connection and clear auth context |
| `Get-AdCloudAuthContext` | Retrieve current authentication context |
| `Get-AdCloudTenantInfo` | Get tenant metadata (ID, domains, created date) |

### Entra ID Discovery

| Function | Purpose |
|----------|---------|
| `Get-AdCloudUsers` | Query all users in Entra ID (with filtering) |
| `Get-AdCloudGroups` | Query all groups (security, M365, distribution) |
| `Get-AdCloudDevices` | Query registered and hybrid-joined devices |
| `Get-AdCloudApplications` | Query app registrations and service principals |
| `Get-AdCloudRoleAssignments` | Query Entra ID role assignments |
| `Get-AdCloudServicePrincipals` | Query service principals |

### Exchange Online Discovery

| Function | Purpose |
|----------|---------|
| `Get-AdCloudMailboxes` | Query user mailboxes with usage stats |
| `Get-AdCloudDistributionGroups` | Query distribution groups and mail-enabled security groups |
| `Get-AdCloudResourceMailboxes` | Query room and equipment mailboxes |
| `Get-AdCloudMailboxPermissions` | Query mailbox access permissions |

### SharePoint & OneDrive Discovery

| Function | Purpose |
|----------|---------|
| `Get-AdCloudSharePointSites` | Query SharePoint sites and site collections |
| `Get-AdCloudOneDriveUsage` | Query OneDrive storage usage by user |
| `Get-AdCloudSitePermissions` | Query site access permissions |

### Teams Discovery

| Function | Purpose |
|----------|---------|
| `Get-AdCloudTeams` | Query Teams with optional channel/member counts |
| `Get-AdCloudTeamChannels` | Query channels within a team |
| `Get-AdCloudTeamMembers` | Query team membership |

### M365 Groups Discovery

| Function | Purpose |
|----------|---------|
| `Get-AdCloudM365Groups` | Query Microsoft 365 Groups with resource linkage |
| `Get-AdCloudGroupMembers` | Query M365 group membership |

### Orchestration & Utilities

| Function | Purpose |
|----------|---------|
| `Invoke-AdCloudDiscovery` | Master orchestration function for all workloads |
| `Export-AdCloudCsv` | Export discovery data to CSV with schema consistency |
| `New-AdCloudLog` | Create timestamped log file |
| `Write-AdCloudLog` | Write entries to log file |

## Configuration

### Configuration Template

See [CloudDiscovery_Config_Template.json](config/CloudDiscovery_Config_Template.json) for configurable options:

```json
{
  "TenantId": "contoso.onmicrosoft.com",
  "ApplicationId": "12345678-1234-1234-1234-123456789012",
  "CertificatePath": "C:\\certs\\cloud-discovery.pfx",
  "Workloads": {
    "EntraID": { "Enabled": true, "IncludeGuestAccounts": true },
    "Exchange": { "Enabled": true, "IncludeArchiveStatus": false },
    "SharePoint": { "Enabled": true, "IncludeStorage": false },
    "Teams": { "Enabled": true, "IncludeMembers": true },
    "M365Groups": { "Enabled": true, "IncludeResources": true }
  }
}
```

### API Permissions Reference

See [API_PERMISSIONS_REFERENCE.md](API_PERMISSIONS_REFERENCE.md) for detailed permissions matrix, minimal vs. extended permission sets, and troubleshooting.

## Usage Examples

### Example 1: Full Discovery with Export

```powershell
# Connect
Connect-AdCloudTenant -TenantId "contoso.onmicrosoft.com" `
  -ClientId "app-id" -CertificatePath "cert.pfx" -CertificatePassword $pwd

# Discover all workloads
$result = Invoke-AdCloudDiscovery -OutputRoot "C:\Reports" -Workloads All `
  -CustomerName "Contoso" -ExportCsv -GenerateReport

# Review
Write-Host "Discovered $($result.TotalRecordsDiscovered) total resources in $($result.DurationSeconds)s"
Get-ChildItem $result.OutputPath
```

### Example 2: Entra ID Only with Filtering

```powershell
# Query active members only
$activeUsers = Get-AdCloudUsers -Filter "accountEnabled eq true and userType eq 'Member'"

# Query security groups
$secGroups = Get-AdCloudGroups -GroupType Security

# Export to CSV
$activeUsers | Export-AdCloudCsv -Path "C:\Reports\ActiveUsers.csv"
$secGroups | Export-AdCloudCsv -Path "C:\Reports\SecurityGroups.csv"
```

### Example 3: Exchange and SharePoint Discovery

```powershell
# Workload-specific discovery
Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\Exchange_SharePoint" `
  -Workloads Exchange, SharePoint

# Query large mailboxes
$largeMailboxes = Get-AdCloudMailboxes |
  Where-Object { $_.TotalItemSize -gt 50GB }

# Query large OneDrive users
$largeOneDrives = Get-AdCloudOneDriveUsage -MinStorageMB 100000  # 100GB+
```

### Example 4: Teams and M365 Groups Analysis

```powershell
# Get teams with channel and member counts
$teams = Get-AdCloudTeams -IncludeChannels -IncludeMembers

# Get M365 groups with associated resources
$m365groups = Get-AdCloudM365Groups -IncludeMembers -IncludeResources

# Find large teams (1000+ members)
$largeTeams = $teams | Where-Object { $_.MemberCount -gt 1000 }

# Export analysis
$teams | Export-AdCloudCsv -Path "C:\Reports\Teams_Summary.csv"
$m365groups | Export-AdCloudCsv -Path "C:\Reports\M365Groups_Summary.csv"
```

### Example 5: Interactive Authentication (Testing)

```powershell
# Connect interactively (prompts for login)
Connect-AdCloudTenant -TenantId "contoso.onmicrosoft.com" -AuthType Interactive

# Query a single workload
$users = Get-AdCloudUsers
$users | Select-Object UserPrincipalName, DisplayName, AccountEnabled | Format-Table

# Disconnect
Disconnect-AdCloudTenant
```

## Output Structure

```
C:\Reports\CloudDiscovery_20260128\
├── 00_schemas/
│   └── Schema_*.csv              # Schema definitions for CSV consistency
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
│   ├── CloudDiscovery_Summary.html
│   └── CloudDiscovery_Analysis.html
└── logs/
    └── discovery__20260128-120000.log
```

## Authentication Methods

### 1. Certificate-Based (Recommended for Production)

Unattended, secure, suitable for scheduled tasks:

```powershell
Connect-AdCloudTenant -TenantId $tenantId -ClientId $appId `
  -CertificatePath "C:\certs\cert.pfx" -CertificatePassword $pwd
```

**Advantages**: Fully automated, no user interaction, certificate rotation, audit trail

### 2. Interactive (Testing & Validation)

User sign-in with browser prompt:

```powershell
Connect-AdCloudTenant -TenantId $tenantId -AuthType Interactive
```

**Advantages**: User-scoped permissions, simple testing

### 3. Device Code Flow (Headless Scenarios)

User signs in on another device:

```powershell
Connect-AdCloudTenant -TenantId $tenantId -ClientId $appId -AuthType DeviceCode
# User opens browser and enters device code
```

**Advantages**: Works in headless/attended environments

## Troubleshooting

### "Not connected to cloud tenant"

```powershell
# Check connection status
$ctx = Get-AdCloudAuthContext
if ($null -eq $ctx) {
    Write-Host "Not connected. Calling Connect-AdCloudTenant..."
    Connect-AdCloudTenant -TenantId $tenantId -ClientId $appId -CertificatePath $cert
}
```

### Module Import Fails

```powershell
# Verify MS-Graph modules installed
Get-Module -ListAvailable | grep Microsoft.Graph

# Install missing modules
Install-Module Microsoft.Graph.Authentication -AllowPrerelease -Force
```

### Permission Denied Errors

```powershell
# Verify service principal has API permissions
# Azure Portal → App Registrations → [Your App] → API permissions
# Ensure "Grant admin consent" shows green checkmark

# Check if service principal is being used
$ctx = Get-AdCloudAuthContext
Write-Host "Auth Type: $($ctx.AuthType)"
Write-Host "Client ID: $($ctx.ClientId)"
```

### Rate Limiting (Too Many Requests)

```powershell
# MS-Graph limits 2000 requests per 10 minutes
# Add delay between queries or use Filter to reduce volume

# Filter to scope query
$users = Get-AdCloudUsers -Filter "accountEnabled eq true"  # Reduces results

# Stagger workload discovery
Get-AdCloudUsers    # Wait for large result sets to complete
Start-Sleep -Seconds 30
Get-AdCloudGroups
```

## Performance Considerations

### Large Tenant Optimization

- **Use Filter parameters** to reduce data volume
- **Avoid IncludeMembers on large workload discovery** (significantly slower)
- **Consider workload-specific queries** instead of full discovery
- **Run during off-peak hours** for scheduled tasks

### Typical Discovery Times

- Small tenant (< 5k users): 5-10 minutes
- Medium tenant (5k-50k users): 15-45 minutes
- Large tenant (50k+ users): 1-2 hours (or longer with IncludeMembers)

## Security Best Practices

1. **Certificate Management**
   - Store .pfx files in secure location (Azure Key Vault, credential manager)
   - Rotate certificates annually
   - Use strong passwords for .pfx encryption

2. **Service Principal Least Privilege**
   - Grant only required API permissions
   - Review and audit permissions quarterly
   - Disable service principal when not in use

3. **Audit and Logging**
   - Enable Azure AD sign-in logs for service principal
   - Monitor MS-Graph API usage
   - Review discovery logs for anomalies

4. **Scheduled Execution**
   - Run with minimal privilege service account (not admin)
   - Use Windows Task Scheduler or Azure Automation
   - Secure output folder with restricted access
   - Rotate and archive old results

## Separation from AD Discovery

This module is completely separate from [Migration.Toolkit](../Migration.Toolkit/) AD discovery:

- **AD Discovery** (`Invoke-AdDiscovery`): On-premises Active Directory
- **Cloud Discovery** (`Invoke-AdCloudDiscovery`): Microsoft 365 / Entra ID

Both can be run independently or in sequence to create comprehensive migration assessments:

```powershell
# Discover on-premises AD
Import-Module .\src\Migration.Toolkit
$adResult = Invoke-AdDiscovery -OutputRoot "C:\Reports\AD_Discovery"

# Discover cloud workloads
Import-Module .\src\Migration.Toolkit.Cloud
Connect-AdCloudTenant -TenantId $tenantId ...
$cloudResult = Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\Cloud_Discovery"

# Results in separate folders for comparison/analysis
```

## References

- [Setup Guide](SETUP_GUIDE.md) - Detailed setup and configuration instructions
- [API Permissions Reference](API_PERMISSIONS_REFERENCE.md) - Permissions matrix and troubleshooting
- [MS-Graph Documentation](https://docs.microsoft.com/en-us/graph/)
- [PowerShell Graph SDK](https://github.com/microsoftgraph/msgraph-sdk-powershell)
- [ExchangeOnlineManagement](https://docs.microsoft.com/en-us/powershell/exchange/)

## License

MIT License - See LICENSE file for details

## Support

For issues or feature requests:
- Check [SETUP_GUIDE.md](SETUP_GUIDE.md) troubleshooting section
- Review API permissions in [API_PERMISSIONS_REFERENCE.md](API_PERMISSIONS_REFERENCE.md)
- Enable verbose logging: `$VerbosePreference = 'Continue'`
