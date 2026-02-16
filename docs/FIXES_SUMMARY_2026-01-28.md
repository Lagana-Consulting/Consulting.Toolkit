# Cloud Discovery Fixes - January 28, 2026

## Issues Fixed

### 1. ✅ Distribution Groups - EXO Connection Detection
**File**: `Get-AzCloudDistributionGroups.ps1`

**Problem**: Function unconditionally returned warning and empty array even when Exchange Online was connected.

**Fix**: Added proper EXO connection detection:
```powershell
if (-not (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
    Write-Warning "Exchange Online Management module not available..."
    return @()
}

$exoConnections = Get-ConnectionInformation -ErrorAction SilentlyContinue
if (-not $exoConnections) {
    Write-Warning "Not connected to Exchange Online. Use Connect-AzCloudTenant -IncludeExchangeOnline..."
    return @()
}

# Actually query EXO
$groups = Get-DistributionGroup -ResultSize Unlimited -ErrorAction Stop
```

**Result**: Function now properly checks if EXO is connected and queries distribution groups when available.

---

### 2. ✅ Resource Mailboxes - EXO Connection Detection
**File**: `Get-AzCloudResourceMailboxes.ps1`

**Problem**: Same as Distribution Groups - unconditional warning despite EXO connection.

**Fix**: Same pattern as Distribution Groups - check `Get-ConnectionInformation` before running:
```powershell
$exoConnections = Get-ConnectionInformation -ErrorAction SilentlyContinue
if (-not $exoConnections) {
    Write-Warning "Not connected to Exchange Online..."
    return @()
}

$mailboxes = Get-Mailbox -RecipientTypeDetails RoomMailbox,EquipmentMailbox -ResultSize Unlimited
```

**Result**: Function now properly detects EXO connection and queries resource mailboxes.

---

### 3. ✅ SharePoint Sites - Root Site Discovery
**File**: `Get-AzCloudSharePointSites.ps1`

**Problem**:
- `Get-MgSite -All $true` was returning 0 sites
- REST fallback `sites?search=*` fails with BadRequest
- Tenants with only root site showed 0 sites

**Fix**: Always query root site first, then try to get additional sites:
```powershell
# Always get root site first
$sites = @()
try {
    $rootResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/root"
    # Convert hashtable to PSCustomObject for consistency
    if ($rootResponse) {
        $sites += [PSCustomObject]$rootResponse
    }
    Write-Verbose "Got root site: $($rootResponse.webUrl)"
}
catch {
    Write-Verbose "Could not get root site: $($_.Exception.Message)"
}

# Try to get additional sites via SDK
try {
    $additionalSites = Get-MgSite @params -ErrorAction Stop
    if ($additionalSites) {
        $sites += $additionalSites
    }
}
catch {
    # Fallback: Try subsites
    $subsiteResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/root/sites"
    if ($subsiteResponse.value) {
        $subsiteResponse.value | ForEach-Object { $sites += [PSCustomObject]$_ }
    }
}

# De-duplicate
$sites = $sites | Where-Object { $_.id } | Sort-Object -Property id -Unique
```

**Result**: Now properly discovers root site plus any additional sites. Handles hashtable vs object conversion correctly.

---

## Connection Workflow Fixed

The `-IncludeExchangeOnline` switch on `Connect-AzCloudTenant` now works correctly:

1. Connects to Microsoft Graph (1st auth prompt)
2. Connects to Exchange Online (2nd auth prompt)
3. EXO connection persists throughout PowerShell session
4. Functions check `Get-ConnectionInformation` to verify EXO availability
5. EXO-dependent functions only run when connection exists

**User Experience**:
```powershell
Connect-AzCloudTenant -TenantId "tenant.onmicrosoft.com" -IncludeExchangeOnline -AuthType Interactive
# User sees 2 auth prompts (Graph + EXO)
# ✓ Connected to Exchange Online

Invoke-AzCloudDiscovery -OutputRoot "C:\Reports" -Workloads All
# All workloads now discover successfully
```

---

## Discovery Results (Test Tenant)

### Before Fixes:
- ❌ Distribution Groups: Warning (not checking connection)
- ❌ Resource Mailboxes: Warning (not checking connection)
- ❌ SharePoint: 0 sites (missing root site)

### After Fixes:
- ✅ Distribution Groups: 0 found (correctly queried, tenant has none)
- ✅ Resource Mailboxes: 0 found (correctly queried, tenant has none)
- ✅ SharePoint: 1 site (root site discovered)
- ✅ Entra ID: 4 users, 7 groups, 2 devices, 103 applications
- ✅ Exchange: 3 mailboxes
- ✅ Teams: 5 teams
- ✅ M365 Groups: 7 groups

**Total Records**: 132
**Errors**: 0
**Duration**: ~8 seconds

---

## Testing Validated

```powershell
# Test 1: EXO Connection Detection
Get-ConnectionInformation
# UserPrincipalName: admin@tenant.onmicrosoft.com
# State: Connected

# Test 2: Distribution Groups
Get-AzCloudDistributionGroups -Verbose
# VERBOSE: Retrieving distribution groups from Exchange Online...
# VERBOSE: Retrieved 0 distribution groups
# (No warning - correctly detected EXO connection)

# Test 3: SharePoint Sites
Get-AzCloudSharePointSites
# webUrl: https://tenant.sharepoint.com
# displayName: Communication site
# Count: 1

# Test 4: Full Discovery
Invoke-AzCloudDiscovery -OutputRoot "C:\Reports" -Workloads All
# DiscoveryErrorCount: 0
# TotalRecordsDiscovered: 132
```

---

## Files Modified

1. `src/Migration.Toolkit.Cloud/Public/Get-AzCloudDistributionGroups.ps1`
2. `src/Migration.Toolkit.Cloud/Public/Get-AzCloudResourceMailboxes.ps1`
3. `src/Migration.Toolkit.Cloud/Public/Get-AzCloudSharePointSites.ps1`

---

## Remaining Notes

- **OneDrive Usage**: Still has issues retrieving usage data (empty UserId errors) - not blocking, just verbose warnings
- **Graph SDK Compatibility**: REST fallbacks remain in place for Devices, Applications, Service Principals due to ongoing SDK issues
- **CSV Export Quality**: Previous session's fixes remain effective (complex Graph properties excluded)
- **Scopes**: Current scopes sufficient for all tested workloads

---

## Deployment Ready

All fixes tested and validated. Module is ready for use with:
- Exchange Online integration via `-IncludeExchangeOnline`
- SharePoint root site discovery
- Proper EXO connection detection
- Zero errors in full discovery runs
