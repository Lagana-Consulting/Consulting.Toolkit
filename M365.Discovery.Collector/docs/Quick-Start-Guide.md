# M365 Discovery Collector - Quick Start Guide

## Copyright Notice
Copyright (c) 2024 Lagana Consulting. All rights reserved.  
Proprietary and confidential.

---

## What This Tool Does
Collects Microsoft 365 and Entra ID (Azure AD) configuration data from your tenant for migration assessment.

---

## Requirements
- **Permissions:** Global Administrator or Global Reader
- **Time:** 15-30 minutes (5 min setup + 10-25 min collection)
- **Windows 10/11** with internet connection

---

## Part 1: Initial Setup (Do This Once)

### 1. Launch the Application
- Double-click `Collector.App.exe`

### 2. Enable Bootstrap Admin Mode
- In the top-right, click the toggle: **"Bootstrap Admin Role"** (turn it ON)
- Status should show: **"Role: Bootstrap Admin"**

### 3. Run Setup Wizard (Click these buttons in order)
1. **🔐 Admin Sign In** → Sign in with Global Admin account
2. **📝 Create App** → Wait for "App registration created"
3. **🔑 Add Perms** → Wait for "Permissions added"
4. **✅ Consent** → Click "Accept" in browser

### 4. Switch Back to Operator Mode
- Click **"Bootstrap Admin Role"** toggle again (turn it OFF)
- Status should show: **"Role: Operator"**

**Setup complete!** You won't need to do this again.

---

## Part 2: Collect Data (Every Time You Run)

### 1. Configure & Sign In
1. Click **"⚙ Configure Auth"**
   - Mode: **Interactive (Delegated)**
   - Tenant ID: Your tenant ID or domain
   - Click **OK**
2. Click **"🔐 Sign In"** → Sign in with your admin account

### 2. Run Preflight Check
- Click **"Preflight Check"**
- Wait for results
- Ensure workloads show green indicators

### 3. Configure Collection Settings
**Left Panel:**
- **Output Folder:** Click "Browse" to choose where files are saved (default: Desktop)
- **Run Name:** Give it a meaningful name (e.g., `CompanyName_Production`)
- **Report Days:** Select **7** (for faster collection) or **30** (for more usage data)

### 4. Select What to Collect
**Quick Options:**
- Click **"Enable Entra ID"** to select all identity data
- Click **"Enable Microsoft 365"** to select all service data

**OR manually check boxes for:**
- ✅ Entra Users
- ✅ Entra Groups
- ✅ Entra Applications
- ✅ Conditional Access
- ✅ M365 Groups
- ✅ Exchange Mailbox Usage
- ✅ OneDrive Usage

### 5. Run Collection
- Click the big **"▶ Run Selected Workloads"** button
- Wait 10-30 minutes (depending on tenant size)
- Watch progress in the right panel

### 6. Access Results
- When complete, click **"Open"** next to Output Folder
- CSV files are ready for analysis

---

## Where's My Data?

Look in the output folder you selected. You'll find CSV files like:
- `EntraUsers.csv` - All user accounts
- `EntraGroups.csv` - All groups
- `ConditionalAccess.csv` - CA policies
- `ExchangeMailboxUsage.csv` - Mailbox statistics
- `OneDriveUsage.csv` - OneDrive statistics
- And more...

---

## Common Issues

| Problem | Solution |
|---------|----------|
| "Auth stale" warning | Click **🔄 Refresh Sign-In** |
| "Insufficient permissions" | Re-run Initial Setup (Part 1) |
| Workload shows red/blocked | Check preflight report; may need licenses |
| Collection fails | Try selecting fewer workloads |
| Need to start over | Click **🔄 Reset** button |

---

## Data Privacy
- All data stays on **your computer**
- Nothing is sent to Lagana Consulting automatically
- Handle exported CSV files per your data policies

---

## Support
Contact Lagana Consulting with:
- Screenshots of errors
- Log messages from the application
- Description of what you were doing

---

**Copyright © 2024 Lagana Consulting. All rights reserved.**
