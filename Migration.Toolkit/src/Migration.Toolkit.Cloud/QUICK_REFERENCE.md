# Quick Reference - Migration.Toolkit.Cloud

## Installation

```powershell
# Import module
Import-Module "C:\path\to\Migration.Toolkit\src\Migration.Toolkit.Cloud" -Force

# Verify
Get-Command -Module Migration.Toolkit.Cloud | Measure-Object
```

## Setup (First Time)

### Automated Setup
```powershell
cd src\Migration.Toolkit.Cloud
.\Setup-CloudDiscoveryServicePrincipal.ps1 -TenantId "contoso.onmicrosoft.com"
# Creates: app registration, certificate, permissions, config file
```

### Manual Setup (if needed)
1. See [SETUP_GUIDE.md](SETUP_GUIDE.md) for step-by-step instructions
2. Run [Setup-CloudDiscoveryServicePrincipal.ps1](Setup-CloudDiscoveryServicePrincipal.ps1) or configure via Azure Portal

## Authentication

### Certificate-Based (Recommended)
```powershell
Connect-AdCloudTenant `
  -TenantId "contoso.onmicrosoft.com" `
  -ClientId "12345678-1234-1234-1234-123456789012" `
  -CertificatePath "C:\certs\cloud-discovery.pfx" `
  -CertificatePassword (ConvertTo-SecureString "password" -AsPlainText -Force)
```

### Interactive (Testing)
```powershell
Connect-AdCloudTenant -TenantId "contoso.onmicrosoft.com" -AuthType Interactive
```

### Verify Connection
```powershell
$ctx = Get-AdCloudAuthContext
Get-AdCloudTenantInfo
```

## Quick Discovery

### Full Discovery (All Workloads)
```powershell
$result = Invoke-AdCloudDiscovery `
  -OutputRoot "C:\Reports\$(Get-Date -Format yyyyMMdd)" `
  -Workloads All `
  -CustomerName "Contoso Inc"

# View results
$result | Format-List
Get-ChildItem $result.OutputPath -Recurse
```

### Workload-Specific Discovery
```powershell
# Entra ID only
Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\EntraID" -Workloads EntraID

# Teams only
Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\Teams" -Workloads Teams

# Exchange + SharePoint
Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\M365" -Workloads Exchange, SharePoint
```

## Individual Workload Queries

### Entra ID
```powershell
$users = Get-AdCloudUsers
$groups = Get-AdCloudGroups
$devices = Get-AdCloudDevices
$apps = Get-AdCloudApplications

# Filtered queries
$activeUsers = Get-AdCloudUsers -Filter "accountEnabled eq true"
$secGroups = Get-AdCloudGroups -GroupType Security
```

### Exchange Online
```powershell
$mailboxes = Get-AdCloudMailboxes
$distGroups = Get-AdCloudDistributionGroups
$resources = Get-AdCloudResourceMailboxes

# Large mailboxes
$large = $mailboxes | Where-Object { $_.TotalItemSize -gt 50GB }
```

### SharePoint & OneDrive
```powershell
$sites = Get-AdCloudSharePointSites
$oneDrive = Get-AdCloudOneDriveUsage

# Large OneDrive accounts
$large = Get-AdCloudOneDriveUsage -MinStorageMB 100000  # 100GB+
```

### Teams
```powershell
$teams = Get-AdCloudTeams -IncludeChannels -IncludeMembers

# Large teams
$large = $teams | Where-Object { $_.MemberCount -gt 500 }
```

### M365 Groups
```powershell
$m365groups = Get-AdCloudM365Groups -IncludeMembers -IncludeResources
```

## Export Results

### Single Workload
```powershell
$users | Export-AdCloudCsv -Path "C:\Reports\Users.csv"
```

### Multiple Workloads
```powershell
Get-AdCloudUsers | Export-AdCloudCsv -Path "C:\Reports\Users.csv"
Get-AdCloudGroups | Export-AdCloudCsv -Path "C:\Reports\Groups.csv"
Get-AdCloudMailboxes | Export-AdCloudCsv -Path "C:\Reports\Mailboxes.csv"
```

## Logging

### Manual Logging
```powershell
$logPath = New-AdCloudLog -Folder "C:\Logs" -Prefix "mydiscovery"
Write-AdCloudLog -Path $logPath -Message "Discovery started"
Write-AdCloudLog -Path $logPath -Message "Completed user query" -Level Info
Write-AdCloudLog -Path $logPath -Message "Warning: slow query" -Level Warning
```

### Automatic Logging
Discovery functions and `Invoke-AdCloudDiscovery` automatically create logs in output folder.

## Cleanup

```powershell
# Disconnect
Disconnect-AdCloudTenant

# Clear context
$ctx = Get-AdCloudAuthContext  # Should return $null
```

## Troubleshooting Quick Fixes

| Issue | Fix |
|-------|-----|
| Module not found | `Install-Module Microsoft.Graph.Authentication -AllowPrerelease` |
| Not connected error | Run `Connect-AdCloudTenant` with cert/interactive auth |
| Permission denied | Verify admin consent in Azure Portal (API permissions → Grant) |
| Slow query | Use Filter to reduce results; avoid IncludeMembers on large sets |
| Module import fails | Run `Import-Module ... -Force`; verify MS-Graph modules installed |

## Advanced Queries

### Find Users with Expiring Passwords
```powershell
$users = Get-AdCloudUsers
$old = $users | Where-Object {
  (Get-Date) - $_.LastPasswordChangeDateTime -gt (New-TimeSpan -Days 180)
}
```

### Teams with Highest Member Count
```powershell
$teams = Get-AdCloudTeams -IncludeMembers
$teams | Sort-Object -Property MemberCount -Descending | Select-Object -First 10
```

### OneDrive Usage Report
```powershell
$oneDrive = Get-AdCloudOneDriveUsage
$oneDrive | Select-Object UserPrincipalName, StorageUsedMB, StoragePercentUsed |
  Sort-Object -Property StorageUsedMB -Descending |
  Export-AdCloudCsv -Path "OneDrive_Report.csv"
```

### Apps with Expiring Certificates
```powershell
$apps = Get-AdCloudApplications
$apps | Where-Object { $_.ExpiredCertCount -gt 0 -or $_.ExpiredSecretCount -gt 0 }
```

## Configuration

See [config/CloudDiscovery_Config_Template.json](config/CloudDiscovery_Config_Template.json) for full configuration options.

## Documentation

- **[README.md](README.md)** - Complete user guide and examples
- **[SETUP_GUIDE.md](SETUP_GUIDE.md)** - Detailed setup instructions
- **[API_PERMISSIONS_REFERENCE.md](API_PERMISSIONS_REFERENCE.md)** - Permissions and troubleshooting
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Architecture and design decisions

## Support

1. Check README.md troubleshooting section
2. Review API_PERMISSIONS_REFERENCE.md for permission issues
3. Enable verbose: `$VerbosePreference = 'Continue'`
4. Check logs in output folder
5. Verify service principal in Azure Portal
