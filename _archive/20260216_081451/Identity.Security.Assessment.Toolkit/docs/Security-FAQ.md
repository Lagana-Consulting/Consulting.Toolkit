# Appendix — Security FAQ  
**Identity Security Assessment**

This appendix addresses common security, risk, and operational questions related to the Identity Security Assessment tooling and approach.

---

## Does this assessment make changes to our environment?
No.  
All assessment activities are **read-only by default**. The toolkit does not modify directory objects, policies, configurations, or permissions.

---

## Are any agents installed on domain controllers or servers?
No.  
All tools are executed from a **dedicated assessment workstation or VM**.  
No software or agents are installed on domain controllers, production servers, or user endpoints.

---

## Does this assessment include exploitation or penetration testing?
No.  
This assessment focuses on **configuration posture, privilege exposure, and identity hygiene**. It does not include:
- Password spraying or cracking
- Exploit execution
- Lateral movement
- Privilege escalation attempts
- Payload delivery or persistence

---

## What type of data is collected?
Collected data includes:
- Directory metadata (users, groups, computers, roles)
- Configuration settings (password policies, Conditional Access policies)
- Relationship and permission data (group membership, delegation paths)
- Authentication posture indicators (e.g., MFA coverage, legacy auth exposure)

Sensitive data **not collected**:
- Passwords or password hashes
- Authentication tokens beyond the current session
- User content (email, files, chats)

---

## Does any data leave our environment?
By default, no.  
All evidence files (CSV/JSON/logs) are generated and stored locally on the assessment workstation or VM.

Data export outside the environment occurs **only with explicit customer approval** and in an agreed format.

---

## What permissions are required?
The assessment is designed to operate with **least privilege**.

- **On-prem AD**: Directory read access
- **Entra ID / M365**: Global Reader or Security Reader (recommended)

Elevated roles (Domain Admin, Global Administrator) are **not required** for the standard assessment and are requested only if explicitly agreed for deeper analysis.

---

## Why are tools like SharpHound or BloodHound used?
When enabled, these tools:
- Collect **read-only directory relationship metadata**
- Help identify **effective permissions and indirect privilege paths**
- Replace time-consuming manual ACL and delegation analysis

They do **not**:
- Attempt authentication attacks
- Perform exploitation
- Modify AD objects

Use of these tools is optional and profile-driven.

---

## Will this impact performance or availability?
No material impact is expected.

- Queries are read-only and low-frequency
- No continuous monitoring or agents are deployed
- Optional deep modules may increase query volume but are scheduled and controlled

---

## How are credentials handled?
- Credentials are entered interactively or via approved authentication methods
- No credentials are stored in scripts or configuration files
- Tokens are held in memory only for the duration of execution

---

## Can we review or approve what will run before execution?
Yes.  
The toolkit is:
- Script-based and transparent
- Profile-driven (clearly defining enabled checks)
- Fully reviewable prior to execution

A pre-assessment validation script (`Test-Prereqs.ps1`) is provided to confirm scope and access before data collection begins.

---

## Can this be run in regulated or restricted environments?
Yes.  
The assessment supports:
- Read-only execution
- Least-privilege access
- Customer-hosted execution
- No outbound data transfer by default

Profiles can be adjusted to align with regulatory or change-control requirements.

---

## What happens after the assessment is complete?
After delivery:
- Evidence can be archived by the customer
- Assessment credentials can be disabled or removed
- The assessment workstation or VM can be decommissioned

No persistent components remain in the environment.

---

## Summary
This Identity Security Assessment is designed to:
- Provide visibility without introducing risk
- Use standard administrative interfaces and APIs
- Respect least-privilege and change-management principles
- Operate transparently and defensibly in enterprise environments
