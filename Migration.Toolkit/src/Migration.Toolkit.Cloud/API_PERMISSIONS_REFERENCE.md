# MS-Graph API Permissions Matrix for Cloud Discovery

## Required Permissions by Workload

### Entra ID Discovery (Users, Groups, Devices, Applications)

| Resource | Permission | Type | Reason |
|----------|-----------|------|--------|
| Users | User.Read.All | Application | Query all user accounts, profiles, sign-in activity |
| Groups | Group.Read.All | Application | Enumerate all security and M365 groups |
| Devices | Device.Read.All | Application | Discover registered and hybrid-joined devices |
| Applications | Application.Read.All | Application | Discover registered apps and service principals |
| Directory | Directory.Read.All | Application | Read organization metadata, roles, settings |

### Exchange Online Discovery (Mailboxes, Distribution Groups, Resources)

| Resource | Permission | Type | Reason |
|----------|-----------|------|--------|
| Mail | Mail.Read | Delegated or Application | Query mailboxes and message properties |
| Calendar | Calendar.Read.All | Application | Access resource calendar settings |
| MailboxSettings | MailboxSettings.Read | Application | Read mailbox configuration and rules |

**Note**: Requires ExchangeOnlineManagement module for detailed mailbox stats (archive status, forwarding rules, resource booking).

### SharePoint & OneDrive Discovery (Sites, Drives, Usage)

| Resource | Permission | Type | Reason |
|----------|-----------|------|--------|
| Sites | Sites.Read.All | Application | Enumerate SharePoint sites and site collections |
| SharePointTenantSettings | SharePointTenantSettings.Read.All | Application | Read tenant-level SharePoint configuration |
| DriveSettings | DriveSettings.Read.All | Application | Access OneDrive storage quotas and settings |

### Teams Discovery (Teams, Channels, Members)

| Resource | Permission | Type | Reason |
|----------|-----------|------|--------|
| Team | Team.ReadBasic.All | Application | Query team properties (name, description, etc.) |
| TeamSettings | TeamSettings.Read.All | Application | Read team settings and guest access policies |
| Channel | Channel.ReadBasic.All | Application | Enumerate channels within teams |
| ChannelMember | ChannelMember.Read.All | Application | Query channel membership |

### Reports & Audit (Optional, for Advanced Analysis)

| Resource | Permission | Type | Reason |
|----------|-----------|------|--------|
| Reports | Reports.Read.All | Application | Access usage reports, sign-in analytics |
| AuditLog | AuditLog.Read.All | Application | Query change logs for compliance/auditing |

## Minimal Permissions Set

For basic discovery (least privilege):

```
User.Read.All
Group.Read.All
Directory.Read.All
Mail.Read
Sites.Read.All
Team.ReadBasic.All
```

## Extended Permissions Set

For comprehensive analysis with risk data and storage:

```
User.Read.All
Group.Read.All
Device.Read.All
Directory.Read.All
Application.Read.All
Mail.Read
MailboxSettings.Read
Calendar.Read.All
Sites.Read.All
SharePointTenantSettings.Read.All
DriveSettings.Read.All
Team.ReadBasic.All
TeamSettings.Read.All
Channel.ReadBasic.All
Reports.Read.All
AuditLog.Read.All
```

## Delegated vs Application Permissions

### Application Permissions (Recommended for Service Principals)

- **Scope**: Entire tenant
- **Authentication**: Certificate-based or client secret
- **Use Case**: Automated, unattended discovery
- **Advantage**: No user context; works 24/7
- **Permission Format**: `Resource.ReadAll`

### Delegated Permissions (Requires User Context)

- **Scope**: Limited to authenticated user's permissions
- **Authentication**: User sign-in (interactive or device code)
- **Use Case**: Interactive queries, testing
- **Advantage**: User-scoped (respects user's access)
- **Permission Format**: `Resource.Read`, `Resource.ReadWrite`

**Cloud Discovery uses Application permissions for unattended execution.**

## How to Grant Permissions

### Method 1: Azure Portal (Manual)

1. Go to **Azure AD** → **App Registrations** → Select your app
2. Click **API Permissions** → **Add a permission**
3. Select **Microsoft Graph** → **Application Permissions**
4. Search for and select required permissions
5. Click **Grant admin consent for [Tenant]** (requires Global Admin or Cloud App Admin)

### Method 2: PowerShell (Automated)

```powershell
# Requires Directory.ReadWrite.All permission or Global Admin
Import-Module Microsoft.Graph.Applications

$appId = "12345678-1234-1234-1234-123456789012"
$tenantId = "contoso.onmicrosoft.com"

# Define required permissions
$permissions = @(
    @{ resourceId = "00000003-0000-0000-c000-000000000000"; id = "df021288-bdef-4463-88db-98f22db89214" }  # User.Read.All
    @{ resourceId = "00000003-0000-0000-c000-000000000000"; id = "5b567255-7703-4780-807c-7be8301ae99b" }  # Group.Read.All
    @{ resourceId = "00000003-0000-0000-c000-000000000000"; id = "3eca3a1a-cb31-4236-b4b4-e3d4ce2c34e5" }  # Directory.Read.All
)

foreach ($perm in $permissions) {
    New-MgApplicationPermissionGrant -ApplicationId $appId `
      -ResourceId $perm.resourceId `
      -PermissionId $perm.id `
      -Scope "Application"
}

Write-Host "Permissions granted."
```

### Method 3: Microsoft Graph Admin Console

Use Microsoft Graph Explorer (https://developer.microsoft.com/en-us/graph/explorer) to verify permissions:

```
GET /me/permissions
```

## Permissions Discovery Requests

Query the app to discover current permissions:

```powershell
# List permissions on app
Get-MgApplicationPermissionGrant -ApplicationId $appId
Get-MgApplicationOAuth2PermissionGrant -ApplicationId $appId
```

## Troubleshooting Permissions

### "Access Denied" Errors

1. Verify admin consent was granted:
   - Azure Portal → App Registration → API Permissions → Check "Grant admin consent"
   - Status should show green checkmark, not yellow warning

2. Verify service principal has permission:
   ```powershell
   Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" |
     Get-MgServicePrincipalAppRoleAssignment
   ```

3. Check delegated scopes (if using delegated flow):
   ```powershell
   Connect-MgGraph -Scopes "User.Read.All" # Will show consented scopes
   Get-MgContext | Select-Object Scopes
   ```

### Insufficient Privileges

- Ensure connecting with Global Admin or sufficient role
- For service principal: Verify enterprise app has "Admin consent required" turned off
- Check if tenant has conditional access policies blocking the service principal

### Rate Limiting (429 Errors)

MS-Graph rate limits: 2,000 requests per 10 minutes per app

- Implement exponential backoff in queries
- Batch requests where possible
- Consider staggering discovery runs across different times

## Compliance and Auditing

### Audit Logs for Service Principal Activity

```powershell
# Query sign-in logs for service principal
$sp = Get-MgServicePrincipal -Filter "appId eq '$appId'"
Get-MgAuditLogDirectoryAudit -Filter "initiatedBy/app/id eq '$($sp.Id)'" -Top 100
```

### Track Permission Usage

Azure AD records permission grants in audit logs:
- **Activity**: "Consent to application"
- **Actor**: Admin account granting consent
- **Details**: Permissions granted, date/time

## References

- [MS-Graph Permissions Reference](https://docs.microsoft.com/en-us/graph/permissions-reference)
- [App Roles vs Delegated Permissions](https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-permissions-and-consent#permission-types)
- [Azure AD App Consent Process](https://docs.microsoft.com/en-us/azure/active-directory/manage-apps/user-admin-consent-workflow)
