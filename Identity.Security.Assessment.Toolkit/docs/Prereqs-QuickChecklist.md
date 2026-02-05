# Identity Security Assessment – Prerequisites Quick Checklist

This checklist summarizes the **minimum requirements** to perform an Identity Security Assessment covering:
- On-premises Active Directory (AD)
- Microsoft Entra ID
- Microsoft 365 (optional, if in scope)

The assessment is **read-only by default** and does **not install agents** on production systems.

---

## Execution Model
☐ One dedicated Windows workstation or VM provided by the customer  
☐ Joined to the customer Active Directory domain  
☐ Used only for assessment activities  
☐ Can be decommissioned after completion  

---

## Operating System & Runtime
☐ Windows Server 2019/2022 **or** Windows 10/11  
☐ Windows PowerShell 5.1 installed  
☐ PowerShell 7.x installed (recommended, not required)  

---

## Required Software (Baseline)
☐ RSAT – Active Directory PowerShell module  
☐ Microsoft Graph PowerShell SDK  

---

## Optional Software (Enterprise / Extended Scope)
☐ SharpHound (collector only, read-only)  
☐ BloodHound Community Edition (local analysis only)  

☐ Exchange Online PowerShell module (if Exchange is in scope)  
☐ PnP.PowerShell (if SharePoint/OneDrive is in scope)  
☐ MicrosoftTeams PowerShell module (if Teams is in scope)  

---

## Active Directory Access
☐ Domain account with read access to directory objects  
☐ Read access to group memberships  
☐ Read access to password policy objects  

Recommended (not required):
☐ Read access to OU security descriptors (delegation analysis)  
☐ Read access to Group Policy Objects  

Not required for standard assessment:
☐ Domain Admin  
☐ Enterprise Admin  

---

## Entra ID / Microsoft 365 Access
☐ Ability to authenticate to Microsoft Graph (interactive or device code)  

Minimum delegated Graph permissions:
☐ Directory.Read.All  
☐ User.Read.All  
☐ Policy.Read.All  

Recommended directory roles:
☐ Global Reader and/or Security Reader  

Optional (extended analysis):
☐ AuditLog.Read.All  
☐ Reports.Read.All  

Not required for standard assessment:
☐ Global Administrator  

---

## Network Connectivity
☐ DNS and LDAP/LDAPS connectivity to domain controllers  
☐ Internet or proxy access to Microsoft Graph endpoints  

---

## Data Handling & Impact
☐ All data collection is read-only  
☐ No configuration changes are made  
☐ No tools are installed on domain controllers  
☐ Evidence is stored locally unless export is explicitly approved  

---

## Pre-Assessment Validation
☐ Run `tools/Test-Prereqs.ps1` from the assessment workstation  
☐ Resolve any **FAIL** results before assessment start  

---

## Summary
This assessment:
- Uses standard Microsoft administration interfaces and APIs
- Operates in read-only mode by default
- Requires least-privilege access
- Avoids production impact and persistent agents
