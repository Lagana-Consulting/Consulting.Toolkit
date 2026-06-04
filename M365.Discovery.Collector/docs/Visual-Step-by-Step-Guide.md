# M365 Discovery Collector - Visual Step-by-Step Guide

## Copyright Notice
Copyright (c) 2024 Lagana Consulting. All rights reserved.

---

## Overview
This guide provides **visual, step-by-step instructions** for using the M365 Discovery Collector GUI application. Follow the screenshots and instructions carefully.

---

# PART 1: Initial Setup (One-Time Only)

## Step 1: Launch the Application

1. Navigate to the folder where you extracted the collector
2. Double-click **`Collector.App.exe`**
3. The main application window will open

![Application Launch](screenshots/01-launch-application.png)
*Screenshot placeholder: Main window showing title "M365 Discovery Collector V2"*

---

## Step 2: Switch to Bootstrap Admin Role

1. Look at the **top-right** section of the toolbar
2. Find the toggle button labeled **"Bootstrap Admin Role"**
3. **Click to enable** the toggle (it should appear pressed/highlighted)
4. Verify the role indicator shows: **"Role: Bootstrap Admin"**

![Enable Bootstrap Role](screenshots/02-enable-bootstrap-role.png)
*Screenshot placeholder: Highlighted Bootstrap Admin Role toggle in ON position*

📋 **What You Should See:**
- Toggle button is active/pressed
- Blue label shows "Role: Bootstrap Admin"
- Log message: "🔐 Role set to Bootstrap Admin..."

---

## Step 3: Admin Sign In

1. Click the **"🔐 Admin Sign In"** button in the toolbar
2. A browser window will open to Microsoft login page
3. Sign in with your **Global Administrator** credentials
4. Accept any consent prompts
5. Close the browser when authentication completes

![Admin Sign In Button](screenshots/03-admin-signin-button.png)
*Screenshot placeholder: Admin Sign In button highlighted*

![Browser Authentication](screenshots/04-browser-auth.png)
*Screenshot placeholder: Microsoft sign-in page in browser*

📋 **What You Should See:**
- Log message: "✅ Admin authentication successful"
- Browser can be closed

---

## Step 4: Create App Registration

1. Click the **"📝 Create App"** button
2. Wait for the process to complete (5-10 seconds)
3. The app registration will be created in your tenant

![Create App Button](screenshots/05-create-app-button.png)
*Screenshot placeholder: Create App button highlighted*

📋 **What You Should See:**
- Log message: "✅ App registration created"
- Log shows Client ID and App Object ID
- Status: "App registered"

---

## Step 5: Add Permissions

1. Click the **"🔑 Add Perms"** button
2. Wait for permissions to be configured (5-10 seconds)

![Add Permissions Button](screenshots/06-add-perms-button.png)
*Screenshot placeholder: Add Perms button highlighted*

📋 **What You Should See:**
- Log message: "✅ Permissions added to app registration"
- Log lists added permissions

---

## Step 6: Grant Admin Consent

1. Click the **"✅ Consent"** button
2. A browser window will open to the Azure admin consent page
3. Review the permissions list
4. Click **"Accept"** to grant consent
5. Close the browser

![Consent Button](screenshots/07-consent-button.png)
*Screenshot placeholder: Consent button highlighted*

![Admin Consent Page](screenshots/08-admin-consent-page.png)
*Screenshot placeholder: Azure admin consent page showing permissions*

📋 **What You Should See:**
- Browser shows "Permissions requested" page
- After accepting, browser shows success message
- Log message: "✅ Admin consent granted"

---

## Step 7: Switch to Operator Role

1. Click the **"Bootstrap Admin Role"** toggle again to **disable** it
2. Verify the role indicator shows: **"Role: Operator"**

![Disable Bootstrap Role](screenshots/09-disable-bootstrap-role.png)
*Screenshot placeholder: Bootstrap Admin Role toggle in OFF position*

📋 **What You Should See:**
- Toggle button is inactive/unpressed
- Blue label shows "Role: Operator"
- Log message: "👤 Role set to Operator..."

---

✅ **Initial setup is complete!** You can now proceed to data collection.

---

# PART 2: Running Data Collection

## Step 1: Configure Authentication

1. Click the **"⚙ Configure Auth"** button

![Configure Auth Button](screenshots/10-configure-auth-button.png)
*Screenshot placeholder: Configure Auth button highlighted*

2. In the dialog that appears:
   - **Authentication Mode:** Select **"Interactive (Delegated)"**
   - **Tenant ID:** Enter your tenant ID or domain (e.g., `contoso.onmicrosoft.com`)
   - **Client ID:** Should be pre-filled from setup
   - Click **"OK"**

![Auth Configuration Dialog](screenshots/11-auth-config-dialog.png)
*Screenshot placeholder: Authentication configuration dialog*

---

## Step 2: Sign In as Operator

1. Click the **"🔐 Sign In"** button
2. Browser opens to Microsoft login
3. Sign in with your admin account
4. Close browser when complete

![Sign In Button](screenshots/12-signin-button.png)
*Screenshot placeholder: Sign In button highlighted*

📋 **What You Should See:**
- Log message: "✅ Authenticated successfully"
- Toolbar shows authentication status

---

## Step 3: Run Preflight Check

1. Click the **"Preflight Check"** button
2. Wait for the check to complete (10-30 seconds)
3. Review results in the right panel

![Preflight Check Button](screenshots/13-preflight-button.png)
*Screenshot placeholder: Preflight Check button highlighted*

![Preflight Results](screenshots/14-preflight-results.png)
*Screenshot placeholder: Right panel showing preflight results with green/yellow/red indicators*

📋 **What You Should See:**
- Right panel shows preflight report
- Workloads have status indicators:
  - 🟢 **Green:** Available
  - 🟡 **Yellow:** Partial
  - 🔴 **Red:** Blocked

---

## Step 4: Configure Output Settings

In the **left panel**, configure your collection settings:

![Output Settings](screenshots/15-output-settings.png)
*Screenshot placeholder: Left panel showing configuration section*

### Output Folder
- **Default:** Your Desktop
- **Click "Browse..."** to select a different location
- **Or type** the path directly

### Run Name
- **Default:** `Discovery_YYYYMMDD_HHMM`
- **Change to:** Something meaningful (e.g., `Contoso_Prod_Jan2024`)

### Report Days
- **Select:** 7, 30, 90, or 180 days
- **Recommended:** Start with **7 days** for faster collection

---

## Step 5: Select Workloads to Collect

Scroll down in the **left panel** to see workload selection:

![Workload Selection](screenshots/16-workload-selection.png)
*Screenshot placeholder: Left panel showing workload checkboxes organized by category*

### Quick Selection Buttons
1. **"Deselect All"** - Uncheck all workloads
2. **"Enable Entra ID"** - Select all Entra ID workloads (recommended)
3. **"Enable Microsoft 365"** - Select all M365 workloads

### Manual Selection
Expand categories and check boxes for specific workloads:

**🔐 Entra ID** (Recommended minimum):
- ✅ Entra Users
- ✅ Entra Groups
- ✅ Entra Applications
- ✅ Conditional Access

**☁️ Microsoft 365**:
- ✅ M365 Groups
- ✅ Exchange Mailbox Usage
- ✅ OneDrive Usage

📋 **Status Indicators:**
- Each workload shows a colored dot:
  - 🟢 Ready to collect
  - 🟡 Partial access
  - 🔴 Blocked

---

## Step 6: Run the Collection

1. Review your selections
2. Click the large **"▶ Run Selected Workloads"** button at the bottom of the left panel

![Run Button](screenshots/17-run-button.png)
*Screenshot placeholder: Large "Run Selected Workloads" button highlighted*

📋 **What You Should See:**
- Collection starts immediately
- Progress appears in the right panel

---

## Step 7: Monitor Progress

Watch the **right panel** for real-time updates:

![Collection Progress](screenshots/18-collection-progress.png)
*Screenshot placeholder: Right panel showing job progress with status, progress bars, and item counts*

### Progress Indicators
- **Status Column:** "Running" → "Success" or "Failed"
- **Progress Column:** Shows items collected (e.g., "1250/1250")
- **Message Column:** Status messages and details

### Typical Duration
- **Small tenant** (< 500 users): 5-10 minutes
- **Medium tenant** (500-5,000 users): 10-20 minutes
- **Large tenant** (> 5,000 users): 20-30+ minutes

---

## Step 8: Collection Complete

When all workloads finish:

![Collection Complete](screenshots/19-collection-complete.png)
*Screenshot placeholder: Right panel showing all workloads with "Success" status*

📋 **What You Should See:**
- Log message: "✅ Collection complete!"
- Summary shows:
  - Total items collected
  - Success/failure counts
  - Output folder location

---

## Step 9: Access Your Results

1. Click the **"Open"** button next to Output Folder

![Open Folder Button](screenshots/20-open-folder-button.png)
*Screenshot placeholder: "Open" button next to output folder path*

2. Windows Explorer opens showing your CSV files

![Output Folder Contents](screenshots/21-output-folder.png)
*Screenshot placeholder: Windows Explorer showing CSV files and metadata JSON files*

### Files You'll See:
- `EntraUsers.csv`
- `EntraGroups.csv`
- `EntraApplications.csv`
- `ConditionalAccess.csv`
- `M365Groups.csv`
- `ExchangeMailboxUsage.csv`
- `OneDriveUsage.csv`
- `run-metadata.json`
- `preflight-report.json`
- And more...

---

# Troubleshooting

## Issue: "Auth stale - Sign in required" Warning

![Auth Stale Warning](screenshots/22-auth-stale.png)
*Screenshot placeholder: Yellow warning banner showing "Auth stale"*

**Solution:**
1. Click **"🔄 Refresh Sign-In"** button
2. Re-authenticate in browser

---

## Issue: Workload Shows "Blocked" Status

![Blocked Workload](screenshots/23-blocked-workload.png)
*Screenshot placeholder: Workload with red indicator and "Blocked" status*

**Solution:**
1. Run **Preflight Check** to see details
2. Check that your account has required permissions
3. Verify tenant has necessary licenses (e.g., Entra ID P1/P2 for Conditional Access)

---

## Issue: Collection Fails or Times Out

![Collection Failed](screenshots/24-collection-failed.png)
*Screenshot placeholder: Workload showing "Failed" status with error message*

**Solution:**
1. Check log messages for specific errors
2. Retry with fewer workloads selected
3. Reduce Report Days to 7
4. Verify internet connectivity

---

## Issue: Need to Start Over

**Solution:**
1. Click the **"🔄 Reset"** button in the toolbar
2. Configuration will be cleared
3. Follow Part 1 (Initial Setup) again

![Reset Button](screenshots/25-reset-button.png)
*Screenshot placeholder: Reset button highlighted in toolbar*

---

# Certificate-Based Authentication (Advanced)

For unattended/scheduled collections, you can use certificate authentication:

![Certificate Auth](screenshots/26-certificate-auth.png)
*Screenshot placeholder: Certificate authentication settings section*

1. Check **"Use app-only certificate sign-in"**
2. Enter **Tenant ID** (required - cannot be "organizations")
3. Enter **Certificate Thumbprint** (preferred)
   - OR **Certificate Subject Name** (alternative)
4. Ensure certificate is installed in **Current User** or **Local Machine** store
5. Certificate must be uploaded to your app registration in Azure Portal

---

# Tips for Success

## ✅ Best Practices
- Run during business hours for support availability
- Start with **7-day reports** for initial assessment
- Select **all Entra ID workloads** for complete identity picture
- Allow **20-30 minutes** for large tenant collections
- Keep the application window open during collection

## ⚠️ Important Notes
- Data is stored **locally** - nothing is sent to Lagana Consulting
- CSV files contain **real tenant data** - handle securely
- Large tenants may have **thousands of rows** per CSV file
- Some features require **specific licenses** (Entra ID P1/P2, M365 E3/E5)

## 🔒 Security Reminders
- Only share CSV files with authorized recipients
- Use secure channels (encrypted email, secure file transfer)
- Delete local copies when analysis is complete
- Follow your organization's data handling policies

---

# Appendix: Button Reference

| Button | Purpose | When to Use |
|--------|---------|-------------|
| 🔐 **Admin Sign In** | Authenticate as admin for setup | Initial setup only (Bootstrap mode) |
| 📝 **Create App** | Create app registration | Initial setup only |
| 🔑 **Add Perms** | Add Graph API permissions | Initial setup only |
| ✅ **Consent** | Grant admin consent | Initial setup only |
| 🔄 **Reset** | Clear saved configuration | When starting over |
| ⚙ **Configure Auth** | Set authentication parameters | Before first sign-in |
| 🔐 **Sign In** | Authenticate as operator | Every collection session |
| 🔄 **Refresh Sign-In** | Re-authenticate when stale | When prompted |
| **Preflight Check** | Verify permissions and access | Before each collection |
| **▶ Run Selected Workloads** | Start data collection | After configuration |
| **Browse...** | Choose output folder | To change save location |
| **Open** | Open output folder | View collected files |

---

# Appendix: Status Indicators

## Workload Status Colors
- 🟢 **Green / Available:** Ready to collect, no issues
- 🟡 **Yellow / Partial:** Some data may be unavailable or limited
- 🔴 **Red / Blocked:** Cannot collect, missing permissions or features

## Collection Status
- **Queued:** Waiting to start
- **Running:** Currently collecting data
- **Success:** Completed successfully
- **Failed:** Encountered errors

---

**Copyright © 2024 Lagana Consulting. All rights reserved.**

---

## Screenshots Directory Structure

To complete this guide, add screenshots to a `screenshots/` folder:

```
docs/
├── User-Guide-GUI-Collector.md
├── Quick-Start-Guide.md
├── Visual-Step-by-Step-Guide.md
└── screenshots/
    ├── 01-launch-application.png
    ├── 02-enable-bootstrap-role.png
    ├── 03-admin-signin-button.png
    ├── 04-browser-auth.png
    ├── 05-create-app-button.png
    ├── 06-add-perms-button.png
    ├── 07-consent-button.png
    ├── 08-admin-consent-page.png
    ├── 09-disable-bootstrap-role.png
    ├── 10-configure-auth-button.png
    ├── 11-auth-config-dialog.png
    ├── 12-signin-button.png
    ├── 13-preflight-button.png
    ├── 14-preflight-results.png
    ├── 15-output-settings.png
    ├── 16-workload-selection.png
    ├── 17-run-button.png
    ├── 18-collection-progress.png
    ├── 19-collection-complete.png
    ├── 20-open-folder-button.png
    ├── 21-output-folder.png
    ├── 22-auth-stale.png
    ├── 23-blocked-workload.png
    ├── 24-collection-failed.png
    ├── 25-reset-button.png
    └── 26-certificate-auth.png
```

Use a screenshot tool (Windows Snipping Tool, Snagit, etc.) to capture these screens while running the application.
