# 📑 Migration.Toolkit Cloud Module - Complete Documentation Index

## 🎯 Start Here

### For Users Getting Started
1. **[CLOUD_MODULE_SUMMARY.md](CLOUD_MODULE_SUMMARY.md)** - Visual overview and quick facts (5 min read)
2. **[src/Migration.Toolkit.Cloud/README.md](src/Migration.Toolkit.Cloud/README.md)** - Complete user guide with examples (15 min read)
3. **[src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md)** - Copy-paste commands (5 min reference)

### For Setup
1. **[src/Migration.Toolkit.Cloud/SETUP_GUIDE.md](src/Migration.Toolkit.Cloud/SETUP_GUIDE.md)** - Detailed setup instructions
   - Prerequisites and module installation
   - Service principal creation (automated or manual)
   - Certificate generation
   - API permissions configuration
2. **[src/Migration.Toolkit.Cloud/Setup-CloudDiscoveryServicePrincipal.ps1](src/Migration.Toolkit.Cloud/Setup-CloudDiscoveryServicePrincipal.ps1)** - Automated setup script (run this!)

### For Permissions Questions
- **[src/Migration.Toolkit.Cloud/API_PERMISSIONS_REFERENCE.md](src/Migration.Toolkit.Cloud/API_PERMISSIONS_REFERENCE.md)** - Complete permissions matrix and troubleshooting

### For Technical Details
- **[src/Migration.Toolkit.Cloud/IMPLEMENTATION_SUMMARY.md](src/Migration.Toolkit.Cloud/IMPLEMENTATION_SUMMARY.md)** - Architecture, design decisions, optional enhancements
- **[CLOUD_EXPANSION_COMPLETE.md](CLOUD_EXPANSION_COMPLETE.md)** - Project completion summary

## 📚 Complete File Structure

```
Migration.Toolkit/
│
├── 📄 PROJECT DOCUMENTATION
│   ├── CLOUD_MODULE_SUMMARY.md              ← Visual overview (START HERE)
│   ├── CLOUD_EXPANSION_COMPLETE.md          ← Project completion
│   └── (This file - Index)
│
└── src/Migration.Toolkit.Cloud/             ← THE MODULE
    │
    ├── 📋 MODULE CORE
    │   ├── Migration.Toolkit.Cloud.psd1
    │   ├── Migration.Toolkit.Cloud.psm1
    │   │
    │   ├── Public/                          (19 function files, 28 exported)
    │   │   ├── Connect-AdCloudTenant.ps1           [Auth]
    │   │   ├── Disconnect-AdCloudTenant.ps1        [Auth]
    │   │   ├── Get-AdCloudAuthContext.ps1          [Auth]
    │   │   ├── Get-AdCloudUsers.ps1                [Entra ID]
    │   │   ├── Get-AdCloudGroups.ps1               [Entra ID]
    │   │   ├── Get-AdCloudDevices.ps1              [Entra ID]
    │   │   ├── Get-AdCloudApplications.ps1         [Entra ID]
    │   │   ├── Get-AdCloudServicePrincipals.ps1    [Entra ID]
    │   │   ├── Get-AdCloudRoleAssignments.ps1      [Entra ID]
    │   │   ├── Get-AdCloudMailboxes.ps1            [Exchange]
    │   │   ├── Get-AdCloudDistributionGroups.ps1   [Exchange]
    │   │   ├── Get-AdCloudResourceMailboxes.ps1    [Exchange]
    │   │   ├── Get-AdCloudMailboxPermissions.ps1   [Exchange]
    │   │   ├── Get-AdCloudSharePointSites.ps1      [SharePoint]
    │   │   ├── Get-AdCloudOneDriveUsage.ps1        [OneDrive]
    │   │   ├── Get-AdCloudSitePermissions.ps1      [SharePoint]
    │   │   ├── Get-AdCloudTeams.ps1                [Teams]
    │   │   ├── Get-AdCloudTeamChannels.ps1         [Teams]
    │   │   ├── Get-AdCloudTeamMembers.ps1          [Teams]
    │   │   ├── Get-AdCloudM365Groups.ps1           [M365 Groups]
    │   │   ├── Get-AdCloudGroupMembers.ps1         [M365 Groups]
    │   │   ├── Invoke-AdCloudDiscovery.ps1         [Orchestration]
    │   │   ├── Export-AdCloudCsv.ps1               [Utilities]
    │   │   ├── New-AdCloudLog.ps1                  [Utilities]
    │   │   ├── Write-AdCloudLog.ps1                [Utilities]
    │   │   └── Get-AdCloudTenantInfo.ps1           [Utilities]
    │   │
    │   └── Private/                         (Ready for expansion)
    │
    ├── 📚 USER DOCUMENTATION
    │   ├── README.md                        ← COMPLETE GUIDE (1700+ lines)
    │   │   - Feature overview
    │   │   - Quick start (3 steps)
    │   │   - 28 function reference table
    │   │   - 5 detailed usage examples
    │   │   - Output structure explanation
    │   │   - Authentication methods
    │   │   - Troubleshooting
    │   │   - Performance tips
    │   │
    │   ├── QUICK_REFERENCE.md               ← COMMANDS (250+ lines)
    │   │   - Quick copy-paste commands
    │   │   - Common queries
    │   │   - Export examples
    │   │   - Troubleshooting table
    │   │
    │   ├── SETUP_GUIDE.md                   ← DETAILED SETUP (650+ lines)
    │   │   - Prerequisites
    │   │   - App registration (3 methods)
    │   │   - API permissions
    │   │   - Certificate generation
    │   │   - Advanced scenarios
    │   │   - Troubleshooting with solutions
    │   │   - Security best practices
    │   │
    │   ├── API_PERMISSIONS_REFERENCE.md     ← PERMISSIONS (450+ lines)
    │   │   - Permissions by workload
    │   │   - Minimal vs Extended sets
    │   │   - Permission granting methods
    │   │   - Troubleshooting
    │   │
    │   ├── IMPLEMENTATION_SUMMARY.md        ← ARCHITECTURE (350+ lines)
    │   │   - Module structure
    │   │   - Design decisions
    │   │   - Optional enhancements
    │   │   - Testing and deployment
    │   │
    │   └── (This index file would go here)
    │
    ├── ⚙️ CONFIGURATION & SETUP
    │   ├── config/
    │   │   └── CloudDiscovery_Config_Template.json
    │   │
    │   └── Setup-CloudDiscoveryServicePrincipal.ps1  ← RUN THIS FOR SETUP
    │       - Creates Azure AD app
    │       - Generates certificate
    │       - Assigns permissions
    │       - Saves configuration
```

## 🚀 Getting Started Paths

### Path 1: Quick Start (15 minutes)
1. Read: [CLOUD_MODULE_SUMMARY.md](CLOUD_MODULE_SUMMARY.md)
2. Read: [QUICK_REFERENCE.md](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md)
3. Run: `Setup-CloudDiscoveryServicePrincipal.ps1`
4. Execute: Sample discovery command

### Path 2: Thorough Setup (1 hour)
1. Read: [README.md](src/Migration.Toolkit.Cloud/README.md)
2. Read: [SETUP_GUIDE.md](src/Migration.Toolkit.Cloud/SETUP_GUIDE.md)
3. Run: `Setup-CloudDiscoveryServicePrincipal.ps1` (or manual setup)
4. Verify: Connection and permissions
5. Test: Individual workload queries

### Path 3: Understanding Architecture (30 minutes)
1. Read: [CLOUD_MODULE_SUMMARY.md](CLOUD_MODULE_SUMMARY.md)
2. Read: [IMPLEMENTATION_SUMMARY.md](src/Migration.Toolkit.Cloud/IMPLEMENTATION_SUMMARY.md)
3. Review: API_PERMISSIONS_REFERENCE.md for details
4. Study: Function signatures in QUICK_REFERENCE.md

### Path 4: Troubleshooting (As needed)
1. [SETUP_GUIDE.md - Troubleshooting](src/Migration.Toolkit.Cloud/SETUP_GUIDE.md#troubleshooting) - Connection/cert issues
2. [API_PERMISSIONS_REFERENCE.md - Troubleshooting](src/Migration.Toolkit.Cloud/API_PERMISSIONS_REFERENCE.md#troubleshooting-permissions) - Permission issues
3. [README.md - Troubleshooting](src/Migration.Toolkit.Cloud/README.md#troubleshooting) - General issues
4. [QUICK_REFERENCE.md - Troubleshooting](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md#troubleshooting-quick-fixes) - Quick fixes

## 📋 What Each Document Contains

### README.md (1700+ lines)
**Purpose**: Complete user guide with examples
**Contents**:
- Feature overview
- Quick start (3 steps)
- Module functions table
- Configuration reference
- Usage examples (5 scenarios)
- Output structure
- Authentication methods
- Troubleshooting guide
- Performance considerations
- Security best practices
- References

**Best for**: New users, comprehensive understanding

### QUICK_REFERENCE.md (250+ lines)
**Purpose**: Quick command reference
**Contents**:
- Installation
- Setup (automated/manual)
- Authentication examples
- Discovery commands
- Workload-specific queries
- Export examples
- Logging
- Cleanup
- Advanced queries
- Configuration reference
- Troubleshooting table

**Best for**: Quick lookups, copy-paste commands

### SETUP_GUIDE.md (650+ lines)
**Purpose**: Step-by-step setup instructions
**Contents**:
- Overview and architecture
- Prerequisites (PowerShell, modules)
- Azure AD app registration (3 methods)
- API permissions configuration
- Certificate generation (3 options)
- Quick start example
- Advanced scenarios
- Output structure
- Troubleshooting (10 issues with solutions)
- Security best practices

**Best for**: Initial setup, detailed troubleshooting

### API_PERMISSIONS_REFERENCE.md (450+ lines)
**Purpose**: Permissions matrix and configuration
**Contents**:
- Required permissions by workload
- Minimal vs Extended permission sets
- Delegated vs Application permissions
- How to grant permissions (3 methods)
- Permissions discovery queries
- Troubleshooting (Access Denied, Insufficient Privileges, Rate Limiting)
- Compliance and auditing
- References

**Best for**: Permission issues, least-privilege configuration

### IMPLEMENTATION_SUMMARY.md (350+ lines)
**Purpose**: Architecture and design documentation
**Contents**:
- Completion status
- Module structure
- Features implemented (8 areas)
- Documentation overview
- Design decisions (6 rationales)
- Usage examples
- Output structure
- Next steps (optional enhancements)
- Testing guidance
- Deployment instructions
- Security considerations

**Best for**: Technical understanding, architecture review

### CLOUD_MODULE_SUMMARY.md (This file)
**Purpose**: Visual overview and project summary
**Contents**:
- What was delivered
- Module file structure
- Key capabilities
- Separate from AD discovery
- Quick start
- Output structure
- Security features
- Documentation summary
- Function count summary
- Verification checklist
- Next steps
- File summary

**Best for**: High-level overview, project summary

### CLOUD_EXPANSION_COMPLETE.md
**Purpose**: Project completion summary
**Contents**:
- What was created overview
- Module contents summary
- Documentation files
- Configuration and setup
- Design features
- Usage examples
- Separation from AD discovery
- Optional enhancements
- Deployment instructions
- Files created
- Next steps
- Security recommendations
- Support resources

**Best for**: Project overview, management summary

## 🎯 Common Tasks Quick Links

| Task | Primary Doc | Secondary Docs |
|------|-------------|----------------|
| **Get Started** | [QUICK_REFERENCE.md](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md) | [README.md](src/Migration.Toolkit.Cloud/README.md) |
| **Setup Service Principal** | [SETUP_GUIDE.md](src/Migration.Toolkit.Cloud/SETUP_GUIDE.md) | [Setup script](src/Migration.Toolkit.Cloud/Setup-CloudDiscoveryServicePrincipal.ps1) |
| **Configure Permissions** | [API_PERMISSIONS_REFERENCE.md](src/Migration.Toolkit.Cloud/API_PERMISSIONS_REFERENCE.md) | [SETUP_GUIDE.md](src/Migration.Toolkit.Cloud/SETUP_GUIDE.md) |
| **Run Discovery** | [QUICK_REFERENCE.md](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md) | [README.md](src/Migration.Toolkit.Cloud/README.md) |
| **Query Individual Workload** | [QUICK_REFERENCE.md](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md) | [README.md](src/Migration.Toolkit.Cloud/README.md) |
| **Troubleshoot Connection** | [SETUP_GUIDE.md](src/Migration.Toolkit.Cloud/SETUP_GUIDE.md) | [README.md](src/Migration.Toolkit.Cloud/README.md) |
| **Troubleshoot Permissions** | [API_PERMISSIONS_REFERENCE.md](src/Migration.Toolkit.Cloud/API_PERMISSIONS_REFERENCE.md) | [SETUP_GUIDE.md](src/Migration.Toolkit.Cloud/SETUP_GUIDE.md) |
| **Export Results** | [QUICK_REFERENCE.md](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md) | [README.md](src/Migration.Toolkit.Cloud/README.md) |
| **Understand Architecture** | [IMPLEMENTATION_SUMMARY.md](src/Migration.Toolkit.Cloud/IMPLEMENTATION_SUMMARY.md) | [CLOUD_MODULE_SUMMARY.md](CLOUD_MODULE_SUMMARY.md) |
| **View All Functions** | [README.md](src/Migration.Toolkit.Cloud/README.md) - Function Reference | - |

## ✅ What You Have

✅ **Complete module** with 28 functions across 5 workloads
✅ **Production-ready** with certificate authentication
✅ **Comprehensive documentation** (3000+ lines across 5 docs)
✅ **Automated setup** script for service principals
✅ **Configuration template** for deployments
✅ **Multiple authentication** methods (cert, interactive, device code)
✅ **Least-privilege** security model
✅ **Independent** from AD discovery module

## 📞 Support Strategy

1. **For errors**: Check README.md or SETUP_GUIDE.md troubleshooting
2. **For permissions**: See API_PERMISSIONS_REFERENCE.md
3. **For commands**: Use QUICK_REFERENCE.md
4. **For setup**: Follow SETUP_GUIDE.md or run automated script
5. **For architecture**: Review IMPLEMENTATION_SUMMARY.md
6. **For examples**: See README.md usage examples

## 🎓 Recommended Reading Order

1. **5 min**: [CLOUD_MODULE_SUMMARY.md](CLOUD_MODULE_SUMMARY.md) - Understand what you have
2. **15 min**: [README.md](src/Migration.Toolkit.Cloud/README.md) - Complete overview
3. **10 min**: Run [Setup-CloudDiscoveryServicePrincipal.ps1](src/Migration.Toolkit.Cloud/Setup-CloudDiscoveryServicePrincipal.ps1) - Initialize
4. **5 min**: [QUICK_REFERENCE.md](src/Migration.Toolkit.Cloud/QUICK_REFERENCE.md) - First commands
5. **As needed**: Other docs as questions arise

**Total time to productive: ~30 minutes**

---

**Questions?** Check the support strategy above or see SETUP_GUIDE.md troubleshooting section.

**Ready to start?** → Run `Setup-CloudDiscoveryServicePrincipal.ps1`
