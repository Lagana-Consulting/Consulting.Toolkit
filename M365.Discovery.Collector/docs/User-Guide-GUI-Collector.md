# M365 Discovery Collector - User Guide

## Copyright Notice
Copyright (c) 2024 Lagana Consulting. All rights reserved.  
Proprietary and confidential. Unauthorized copying or distribution is prohibited.

---

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Initial Setup (One-Time Configuration)](#initial-setup-one-time-configuration)
4. [Running the Data Collection](#running-the-data-collection)
5. [Understanding the Results](#understanding-the-results)
6. [Troubleshooting](#troubleshooting)

---

## Overview

The **M365 Discovery Collector** is a desktop application that gathers configuration and usage data from your Microsoft 365 tenant, including:
- **Entra ID** (Azure Active Directory) objects: users, groups, applications, service principals, roles
- **Microsoft 365 services**: Exchange mailbox usage, OneDrive usage, M365 Groups
- **Security configuration**: Conditional Access policies, authentication methods, cross-tenant access

This data is exported as CSV files for analysis and migration planning.

---

## Prerequisites

### Required Permissions
You need **Global Administrator** or **Global Reader** permissions in your Microsoft 365 tenant to complete the initial setup and data collection.

### Software Requirements
- Windows 10/11 or Windows Server 2016+
- .NET 8 Runtime (installed automatically with the application)
- Internet connectivity to access Microsoft Graph API

### What You'll Need
- Your **Tenant ID** (found in Azure Portal → Entra ID → Overview)
- Admin credentials for your Microsoft 365 tenant

---

## Initial Setup (One-Time Configuration)

The first time you run the collector, you must configure authentication. Follow these steps:

### Step 1: Launch the Application
1. Extract the application files to a folder (e.g., `C:\M365Collector`)
2. Double-click `Collector.App.exe` to launch the application
3. The main window will open showing "M365 Discovery Collector V2"

### Step 2: Switch to Bootstrap Admin Role
1. In the top-right section of the toolbar, locate the **"Bootstrap Admin Role"** toggle button
2. Click the toggle to **enable** Bootstrap Admin Role
3. The active role indicator should now show **"Role: Bootstrap Admin"**
4. A message will appear in the log: *"🔐 Role set to Bootstrap Admin"*

> **Note:** Bootstrap Admin mode is used only for initial setup. You'll switch back to Operator mode for data collection.

### Step 3: Sign In as Administrator
1. Click the **"🔐 Admin Sign In"** button in the toolbar
2. A browser window will open asking you to sign in to Microsoft
3. Sign in with your **Global Administrator** account
4. Grant consent when prompted
5. Close the browser when authentication completes
6. The log will show: *"✅ Admin authentication successful"*

### Step 4: Create App Registration
1. Click the **"📝 Create App"** button
2. The application will automatically create an app registration in your Entra ID tenant
3. Wait for the confirmation message: *"✅ App registration created"*
4. The app details (Client ID and Object ID) will be saved automatically

### Step 5: Add Required Permissions
1. Click the **"🔑 Add Perms"** button
2. The application will configure the necessary Microsoft Graph API permissions
3. Wait for confirmation: *"✅ Permissions added to app registration"*

### Step 6: Grant Admin Consent
1. Click the **"✅ Consent"** button
2. A browser window will open to the Azure admin consent page
3. Review the permissions requested (read-only access to Entra ID and M365 data)
4. Click **"Accept"** to grant consent
5. Close the browser when complete
6. The log will show: *"✅ Admin consent granted"*

### Step 7: Switch to Operator Role
1. Click the **"Bootstrap Admin Role"** toggle button to **disable** it
2. The active role indicator should now show **"Role: Operator"**
3. A message will appear: *"👤 Role set to Operator"*

**Initial setup is now complete!** The configuration has been saved and you can proceed to data collection.

---

## Running the Data Collection

### Step 1: Configure Authentication
1. Ensure you're in **Operator** role (toggle is OFF)
2. Click the **"⚙ Configure Auth"** button
3. In the configuration dialog:
   - Select **"Interactive (Delegated)"** authentication mode
   - Enter your **Tenant ID** or tenant domain (e.g., `contoso.onmicrosoft.com`)
   - The Client ID should auto-populate from the initial setup
4. Click **"OK"** to save

> **Alternative:** For unattended/scheduled runs, you can use **certificate-based authentication**. Check the "Use app-only certificate sign-in" box and provide certificate details.

### Step 2: Sign In
1. Click the **"🔐 Sign In"** button
2. A browser window will open
3. Sign in with your admin account (can be Global Reader or Global Administrator)
4. Grant consent if prompted
5. Close the browser when complete
6. The log will show: *"✅ Authenticated successfully"*

### Step 3: Run Preflight Check
1. Click the **"Preflight Check"** button
2. The application will verify:
   - Authentication is working
   - Required permissions are available
   - Microsoft Graph connectivity is functional
3. Review the preflight results in the right panel
4. Look for workloads showing **"Available"** status (green indicator)

> **Important:** If any workloads show "Blocked" or "Partial" status, you may need to adjust permissions or enable features in your tenant.

### Step 4: Configure Output Settings
In the left panel, configure where data will be saved:

1. **Output Folder:**
   - Default: Your Desktop
   - Click **"Browse..."** to select a different folder
   - Or manually type the path

2. **Run Name:**
   - Default: `Discovery_YYYYMMDD_HHMM` (timestamp)
   - Change this to identify your collection (e.g., `CompanyName_Production_Jan2024`)

3. **Report Days:**
   - Select **7, 30, 90, or 180 days** for usage reports
   - This determines the period for Exchange and OneDrive usage data
   - Default: 7 days (recommended for initial runs)

### Step 5: Select Workloads to Collect
In the left panel, select which data sets to collect:

#### Quick Selection Options:
- **"Deselect All"** - Uncheck all workloads
- **"Enable Entra ID"** - Select all Entra ID workloads (recommended)
- **"Enable Microsoft 365"** - Select all M365 service workloads

#### Manual Selection:
Expand each category and check the boxes for specific workloads:

**🔐 Entra ID** (Core identity data - recommended):
- ✅ Entra Users
- ✅ Entra Groups
- ✅ Entra Applications
- ✅ Entra Service Principals
- ✅ Entra Roles
- ✅ Guest Users
- ✅ Conditional Access
- ✅ Authentication Methods Coverage
- ✅ App Assignments
- ✅ App Credentials
- ✅ Cross-Tenant Access

**☁️ Microsoft 365** (Usage and service data):
- ✅ M365 Groups
- ✅ Exchange Mailbox Usage (requires Report Days setting)
- ✅ OneDrive Usage (requires Report Days setting)

**🏢 Organization** (Tenant configuration):
- ✅ Organization
- ✅ Hybrid Azure AD Connect Config
- ✅ Directory Settings

> **Tip:** For a comprehensive assessment, select all workloads. Each workload shows a status indicator:
> - 🟢 **Green:** Available and ready to collect
> - 🟡 **Yellow:** Partial access or warnings
> - 🔴 **Red:** Blocked or insufficient permissions

### Step 6: Run the Collection
1. Review your selections in the left panel
2. Click the large **"▶ Run Selected Workloads"** button at the bottom
3. The collection will start, and you'll see:
   - Progress bars for each workload
   - Real-time status updates in the right panel
   - Item counts as data is collected

### Step 7: Monitor Progress
Watch the right panel for collection progress:
- **Status column:** Shows "Running", "Success", or "Failed"
- **Progress column:** Shows X/Y items collected
- **Message column:** Provides details or error messages

> **Note:** Large tenants may take 10-30 minutes depending on the amount of data and selected workloads.

### Step 8: Collection Complete
When all workloads finish:
1. The log will show: *"✅ Collection complete!"*
2. A summary will display:
   - Total items collected
   - Success/failure count
   - Output location
3. Click **"Open"** next to the Output Folder to view the results

---

## Understanding the Results

### Output Folder Structure
After collection, your output folder will contain:

```
Discovery_YYYYMMDD_HHMM/
├── run-metadata.json          # Collection metadata
├── preflight-report.json      # Permission check results
├── EntraUsers.csv            # User account details
├── EntraGroups.csv           # Group details
├── EntraApplications.csv     # Application registrations
├── EntraServicePrincipals.csv # Enterprise applications
├── EntraRoles.csv            # Role assignments
├── GuestUsers.csv            # External users
├── ConditionalAccess.csv     # CA policies
├── AuthMethodsCoverage.csv   # MFA status
├── M365Groups.csv            # Microsoft 365 Groups
├── ExchangeMailboxUsage.csv  # Mailbox statistics
├── OneDriveUsage.csv         # OneDrive statistics
├── Organization.csv          # Tenant info
├── HybridAadConnectConfig.csv # Sync configuration
└── DirectorySettings.csv     # Directory configuration
```

### CSV File Contents
Each CSV file contains:
- **Column headers** describing each field
- **One row per object** (user, group, application, etc.)
- **Timestamps** in ISO 8601 format (UTC)
- **Empty values** where data is not available

### Metadata Files
- **run-metadata.json:** Collection details (run name, timestamp, workloads collected)
- **preflight-report.json:** Permission check results and capability matrix

---

## Troubleshooting

### Authentication Issues

#### "Sign in required" or "Auth stale"
**Solution:** Click the **"🔄 Refresh Sign-In"** button and re-authenticate.

#### "Insufficient permissions"
**Solution:** 
1. Verify you're signed in as a Global Administrator or Global Reader
2. Re-run the initial setup process to ensure permissions are granted
3. Check that admin consent was completed (Step 6 of Initial Setup)

#### "Tenant mismatch" error
**Solution:** Ensure the Tenant ID in Configuration matches your actual tenant.

### Collection Issues

#### Workloads showing "Blocked" status
**Cause:** Missing API permissions or tenant features not enabled

**Solution:**
1. Click **"Preflight Check"** to see detailed permission status
2. Review the preflight report for specific missing permissions
3. In Azure Portal, navigate to your app registration and verify Microsoft Graph permissions
4. Ensure admin consent is granted for all permissions

#### "Access denied" for specific workloads
**Cause:** Some features require specific licenses or tenant configurations

**Solution:**
- **Exchange/OneDrive Usage:** Requires active Microsoft 365 licenses
- **Conditional Access:** Requires Entra ID P1/P2 licenses
- **Privileged Identity Management:** Requires Entra ID P2

#### Collection hangs or times out
**Solution:**
1. Check your internet connection
2. Retry the collection with fewer workloads selected
3. Increase Report Days to a smaller value (e.g., 7 instead of 180)

### General Issues

#### Application won't start
**Solution:**
1. Ensure .NET 8 Runtime is installed
2. Right-click `Collector.App.exe` → Properties → Unblock
3. Run as Administrator if needed

#### "Cannot access output folder"
**Solution:**
1. Verify the output folder path exists
2. Ensure you have write permissions to the folder
3. Try using a different folder (e.g., `C:\Temp`)

#### Need to start over
**Solution:**
1. Click the **"🔄 Reset"** button to clear saved configuration
2. Follow the Initial Setup steps again from the beginning

---

## Support

If you encounter issues not covered in this guide:
1. Check the log panel in the application for detailed error messages
2. Save the output folder contents for review
3. Contact Lagana Consulting with:
   - Screenshots of error messages
   - Log file contents
   - Description of steps taken

---

## Data Privacy Note

All data collected by this tool:
- Is stored locally on your computer in CSV format
- Is **not** transmitted to Lagana Consulting or any third party
- Contains **real tenant data** including user names, email addresses, and configuration
- Should be handled according to your organization's data protection policies

The "Hashed Names" feature (ℹ️ button) provides information about privacy options for usage reports.

---

**Last Updated:** 2024
**Version:** 2.0
**Copyright:** © 2024 Lagana Consulting. All rights reserved.
