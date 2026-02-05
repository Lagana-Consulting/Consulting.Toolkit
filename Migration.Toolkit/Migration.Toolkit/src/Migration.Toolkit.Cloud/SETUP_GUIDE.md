# Migration.Toolkit.Cloud - Cloud Workload Discovery Setup Guide

## Overview

The `Migration.Toolkit.Cloud` module provides comprehensive discovery of Microsoft cloud workloads including Entra ID, Exchange Online, SharePoint, Teams, and Microsoft 365 Groups. It is designed with least-privilege access in mind, supporting certificate-based authentication via enterprise applications (service principals).

## Architecture

- **Separate from AD Discovery**: Cloud functions are in distinct module (`Migration.Toolkit.Cloud`) invoked separately from AD discovery
- **Least Privilege**: Uses certificate-based service principal authentication by default
- **MS-Graph Primary**: Leverages MS-Graph for Entra ID and M365 workloads
- **Structured Output**: Organizes discovery results by workload into timestamped folder structure

## Prerequisites

### 1. PowerShell Version
- **PowerShell 5.1+** (Core 7+ recommended for performance)

### 2. Required PowerShell Modules
Install the Microsoft Graph SDK modules:

```powershell
# Core authentication
Install-Module Microsoft.Graph.Authentication -AllowPrerelease
Install-Module Microsoft.Graph.Users
Install-Module Microsoft.Graph.Groups
Install-Module Microsoft.Graph.DeviceManagement
Install-Module Microsoft.Graph.Applications
Install-Module Microsoft.Graph.Organization

# Mail and Exchange
Install-Module Microsoft.Graph.Mail
Install-Module Microsoft.Graph.Mail.Shared
Install-Module ExchangeOnlineManagement -AllowPrerelease

# Teams and SharePoint
Install-Module Microsoft.Graph.Teams
Install-Module Microsoft.Graph.Sites
Install-Module Microsoft.Graph.Files

# Reports (optional, for advanced queries)
Install-Module Microsoft.Graph.Reports
```

### 3. Azure AD Application Registration (Service Principal)

#### Option A: Create via Azure Portal

1. Go to **Azure Portal** → **Azure AD** → **App registrations** → **New registration**
2. Name: `Cloud Discovery Service Principal` (or similar)
3. Supported account types: **Single tenant** (unless multi-tenant needed)
4. Click **Register**

#### Option B: Create via PowerShell (requires Directory.ReadWrite.All permission)

```powershell
$app = New-MgApplication -DisplayName "Cloud Discovery Service Principal" `
  -SignInAudience "AzureADMyOrg" `
  -Description "Service principal for automated cloud workload discovery"

# Copy the AppId for use in certificate auth
Write-Host "Application ID: $($app.AppId)"
```

### 4. Configure API Permissions

In the registered app, add the following API permissions:

#### Entra ID Discovery
- **User.Read.All** (Application)
- **Group.Read.All** (Application)
- **Device.Read.All** (Application)
- **Application.Read.All** (Application)
- **Directory.Read.All** (Application)

#### Exchange Online Discovery
- **Mail.Read** (Delegated or Application)
- **Calendar.Read.All** (Application)
- **Mailbox.Migration** (Application) *(if available)*

#### SharePoint & OneDrive
- **Sites.Read.All** (Application)
- **SharePointTenantSettings.Read.All** (Application)
- **DriveSettings.Read.All** (Application)

#### Teams Discovery
- **Team.ReadBasic.All** (Application)
- **TeamSettings.Read.All** (Application)
- **Channel.ReadBasic.All** (Application)

#### Reports
- **Reports.Read.All** (Application)
- **AuditLog.Read.All** (Application)

**After adding permissions, click "Grant admin consent for [Tenant]"** to approve.

### 5. Create and Install Certificate

#### Option A: Generate Self-Signed Certificate (Dev/Lab)

```powershell
# Create 2-year self-signed cert
$cert = New-SelfSignedCertificate -CertStoreLocation "Cert:\CurrentUser\My" `
  -Subject "CN=CloudDiscoverySP" `
  -KeyUsage DigitalSignature `
  -Type CodeSigningCert `
  -NotAfter (Get-Date).AddYears(2)

# Export to .pfx (with password)
$certPath = "C:\certs\cloud-discovery.pfx"
$password = ConvertTo-SecureString "YourSecurePassword" -AsPlainText -Force
Export-PfxCertificate -Cert $cert -FilePath $certPath -Password $password

Write-Host "Certificate exported to: $certPath"
Write-Host "Thumbprint: $($cert.Thumbprint)"
```

#### Option B: Use Existing Corporate Certificate

If your organization has an internal PKI:

```powershell
# Request certificate signed by your CA with:
# - Key Usage: Digital Signature
# - Enhanced Key Usage: Client Authentication
# - Store in local machine or user cert store
```

#### Option C: Azure AD Certificate Upload

Once you have a certificate (.cer or .pfx):

```powershell
# Via PowerShell
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @("path\to\cert.cer")
New-MgApplicationKeyCredential -ApplicationId $appId -KeyCredential @{
  type = "AsymmetricX509Cert"
  usage = "Sign"
  key = [System.Convert]::ToBase64String($cert.RawData)
}

# Or in Azure Portal:
# App Registration → Certificates & secrets → Upload Certificate
```

## Quick Start

### 1. Connect with Certificate Authentication

```powershell
# Import cloud module
Import-Module "C:\path\to\Migration.Toolkit.Cloud" -Force

# Connect to tenant with certificate
Connect-AdCloudTenant `
  -TenantId "contoso.onmicrosoft.com" `
  -ClientId "12345678-1234-1234-1234-123456789012" `
  -CertificatePath "C:\certs\cloud-discovery.pfx" `
  -CertificatePassword (ConvertTo-SecureString "YourSecurePassword" -AsPlainText -Force)

# Verify connection
Get-AdCloudAuthContext
Get-AdCloudTenantInfo
```

### 2. Execute Cloud Discovery

```powershell
# Full discovery of all workloads
$result = Invoke-AdCloudDiscovery `
  -OutputRoot "C:\Reports\Contoso_Cloud_$(Get-Date -Format yyyyMMdd)" `
  -Workloads All `
  -CustomerName "Contoso Inc" `
  -ExportCsv `
  -GenerateReport

# View results
$result | Format-Table
```

### 3. Individual Workload Queries

```powershell
# Query specific workloads
$users = Get-AdCloudUsers
$groups = Get-AdCloudGroups
$teams = Get-AdCloudTeams
$m365groups = Get-AdCloudM365Groups
$mailboxes = Get-AdCloudMailboxes
$sites = Get-AdCloudSharePointSites

# Export to CSV
$users | Export-AdCloudCsv -Path "C:\Reports\EntraID_Users.csv"
```

### 4. Disconnect

```powershell
Disconnect-AdCloudTenant
```

## Advanced Scenarios

### Interactive Authentication (Testing)

For quick testing without certificates:

```powershell
Connect-AdCloudTenant -TenantId "contoso.onmicrosoft.com" -AuthType Interactive
# Prompts for user credentials
```

### Device Code Flow (Headless/Attended Scenarios)

```powershell
Connect-AdCloudTenant -TenantId "contoso.onmicrosoft.com" `
  -ClientId "12345678-1234-1234-1234-123456789012" `
  -AuthType DeviceCode
# Displays code; user signs in on another device
```

### Scope-Limited Queries

```powershell
# Only enabled users, exclude guests
$activeMembers = Get-AdCloudUsers -Filter "accountEnabled eq true and userType eq 'Member'"

# Only security groups
$secGroups = Get-AdCloudGroups -GroupType Security

# Teams with high member counts
$largeTeams = Get-AdCloudTeams -IncludeMembers | Where-Object { $_.MemberCount -gt 500 }

# Large OneDrive users
$largeOneDrives = Get-AdCloudOneDriveUsage -MinStorageMB 50000  # 50GB+
```

### Workload-Specific Discovery

```powershell
# Exchange-only discovery
Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\Exchange_Only" -Workloads Exchange

# Teams-only discovery
Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\Teams_Only" -Workloads Teams

# Multiple specific workloads
Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\M365" -Workloads Teams, M365Groups, SharePoint
```

## Output Structure

```
C:\Reports\Contoso_Cloud_20260128\
├── 00_schemas/
│   ├── Schema_Users.csv
│   ├── Schema_Groups.csv
│   └── ...
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
    ├── discovery__20260128-120000.log
    └── ...
```

## Troubleshooting

### "Not connected to cloud tenant"

```powershell
# Verify connection
$ctx = Get-AdCloudAuthContext
if (-not $ctx) {
  Write-Host "Not connected. Running Connect-AdCloudTenant..."
  Connect-AdCloudTenant -TenantId "contoso.onmicrosoft.com" -ClientId "..." ...
}
```

### Certificate Authentication Fails

```powershell
# Verify certificate installed
Get-ChildItem -Path Cert:\CurrentUser\My -Thumbprint "THUMBPRINT"

# Verify certificate in Azure AD
# Azure Portal → App Registration → Certificates & secrets
```

### MS-Graph Module Not Found

```powershell
# Install missing module
Install-Module Microsoft.Graph.Users -AllowPrerelease -Force

# Reimport cloud module
Import-Module "C:\path\to\Migration.Toolkit.Cloud" -Force
```

### Permission Denied Errors

```powershell
# Verify admin consent granted in Azure Portal
# App Registration → API permissions → Grant admin consent for [Tenant]

# Verify service principal has permissions
# Application Registrations → [Your App] → API permissions
```

## Security Best Practices

1. **Certificate Storage**
   - Store .pfx files in secure location (not version control)
   - Use group managed service account (gMSA) if running as scheduled task
   - Rotate certificates annually

2. **Secret Management**
   - Store certificate password in Azure Key Vault or credential manager
   - Never hardcode secrets in scripts
   - Use `-CertificatePath` without password parameter for cert-store-installed certs

3. **Audit Logging**
   - Enable Azure AD sign-in logs for service principal (Azure Portal → Sign-ins)
   - Review discovery logs for anomalies
   - Monitor Graph API usage via Azure AD

4. **Least Privilege**
   - Grant only required API permissions to service principal
   - Review and remove unused permissions quarterly
   - Consider role-based access control (RBAC) in Azure AD

5. **Scheduled Execution**
   - Use Windows Task Scheduler or Azure Automation for regular discovery
   - Run with minimal privileges (service account, not admin)
   - Rotate output folders and archive old results

## Support

For issues, refer to:
- MS-Graph Documentation: https://docs.microsoft.com/en-us/graph/
- PowerShell Graph SDK: https://github.com/microsoftgraph/msgraph-sdk-powershell
- ExchangeOnlineManagement: https://docs.microsoft.com/en-us/powershell/exchange/

## References

- [MS-Graph Authentication Flows](https://docs.microsoft.com/en-us/graph/auth/)
- [Service Principal with Certificate](https://docs.microsoft.com/en-us/azure/active-directory/develop/certificate-credentials)
- [Azure AD App Registration API Permissions](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-permissions-and-consent)
