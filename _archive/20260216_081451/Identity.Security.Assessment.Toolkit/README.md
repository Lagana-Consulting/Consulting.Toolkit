# Identity Security Assessment Toolkit

PowerShell-based security assessment toolkit focused on identity and infrastructure posture. Provides discovery, controlled checks, and evidence packaging with consistent, automation-friendly output schemas.

## Scope
1) Asset + identity discovery (low risk)
- Host inventory (OS, patch level, services, open ports)
- AD / Entra posture snapshots (counts, risky configs, stale objects)
- Baseline security controls presence (Defender, firewall, disk encryption)

2) Vulnerability & misconfig checks (controlled)
- Authenticated vulnerability scanning (when allowed)
- Configuration checks (CIS-ish) for Windows/Linux basics
- AD misconfig indicators (delegation, weak GPO settings, risky groups)

3) Evidence packaging + reporting
- Timestamped outputs (JSON/CSV) + zipped evidence bundle
- Summary tables and top findings with severity mapping
- Reproducible command log (commands + versions)

## Minimum viable commands (first milestone)
1. Invoke-SATDiscovery
	- Inputs: target list (CIDRs, hostnames), optional creds
	- Outputs: hosts.csv, ports.csv, services.json, dns.csv
2. Invoke-SATADSnapshot
	- Outputs: ad_users.csv, ad_groups.csv, privileged_groups.csv, gpo_summary.csv, stale_computers.csv
3. Invoke-SATWebScan
	- Inputs: URL list
	- Outputs: zap_report.html, tls_report.txt, http_headers.csv
4. Invoke-SATPackageEvidence
	- Zips outputs + logs + tool versions into one file
	- Generates Assessment_Summary.md (or JSON) for deliverable pipeline

## Guardrails (client-safe defaults)
- Profiles: LowImpact, Standard, Deep
- Explicit consent gates for intrusive actions
- Rate limits and exclusions (max-rate, scan-delay, exclude subnets)
- Full logging (command line + tool versions + timestamps)
- Credential hygiene (no credential files; prompt or secret store)
- Output normalization (stable CSV/JSON schemas)

## Evidence schema standards (future-proof)
Consistent columns and predictable filenames make reporting and automation reliable.

hosts.csv
- Target, IP, Hostname, OSGuess, FirstSeen, LastSeen, SourceTool

ports.csv
- IP, Port, Proto, State, Service, Version, ScanProfile, Timestamp

findings.csv
- FindingId, Title, Severity, Asset, EvidenceRef, Recommendation, Tool, Timestamp

## Tool stack (planned integrations)
Endpoint / Network
- Nmap (discovery + port/service fingerprinting)
- RustScan (fast port discovery; optional)
- Wireshark/tshark (packet capture when needed)
- OpenVAS / Greenbone Community Edition or Nuclei
- Nuclei templates (fast checks; great for web + misconfigs)

Web app / HTTP
- OWASP ZAP (active/passive web scanning)
- Nikto (legacy web server checks; use sparingly)
- testssl.sh or sslscan (TLS posture)

AD / Windows posture
- BloodHound Community Edition + SharpHound (collection)
- PingCastle (AD health & risk)
- Sysinternals (optional)

Cloud / containers (optional)
- ScoutSuite (cloud security posture)
- Prowler (AWS), AzTS/AzSK successors, Cloud Custodian (policy-as-code)
- Trivy (container/image/IaC scanning)

## Profiles
Profiles live in src/config/profiles and control thresholds, scope, and safety limits.
- LowImpact: discovery only, minimal traffic
- Standard: adds safe configuration checks
- Deep: enables intrusive checks when consented

## Evidence output structure
output/
  <AssessmentName>_<Timestamp>/
	 logs/
	 discovery/
	 ad/
	 web/
	 findings/
	 Assessment_Summary.md

## Build plan
Phase 1 — Framework + Discovery
- Repo scaffold + src/config profile system
- Nmap wrapper + output parsers
- Evidence packaging + logs

Phase 2 — AD posture module
- BloodHound/SharpHound orchestration (collection only)
- High-signal AD checks (privileged group membership, unconstrained delegation, stale objects)

Phase 3 — Web module
- ZAP baseline scan automation
- TLS checks via testssl.sh
- Normalize to findings.csv

Phase 4 — Optional vuln scanning
- OpenVAS/GVM integration or external dependency
- Nuclei templates for quick wins

## Requirements
- PowerShell 7+
- External tools installed and available in PATH as needed per module

## Notes
This toolkit is designed to be safe-by-default. Intrusive actions require explicit consent flags and are gated by profiles.

## Dependency layout: Migration.Toolkit reuse
Identity.Security.Assessment.Toolkit should **depend on** Migration.Toolkit and wrap its AD discovery/analysis functions instead of re-implementing them.

### Module dependency contract
- Identity.Security.Assessment.Toolkit declares Migration.Toolkit as a required module in its manifest.
- Identity.Security.Assessment.Toolkit imports Migration.Toolkit at runtime and **only** calls exported functions.
- All AD-related output is **normalized** into this toolkit’s evidence schemas.

### PowerShell module manifest
Add to [src/Identity.Security.Assessment.Toolkit.psd1](src/Identity.Security.Assessment.Toolkit.psd1):
- `RequiredModules = @(@{ ModuleName = 'Migration.Toolkit'; ModuleVersion = 'x.y.z' })`
- Optional: `CompatiblePSEditions = @('Core')` to align versions

### Runtime import and guardrails
In [src/Identity.Security.Assessment.Toolkit.psm1](src/Identity.Security.Assessment.Toolkit.psm1):
- `Import-Module Migration.Toolkit -MinimumVersion x.y.z -ErrorAction Stop`
- Detect availability and fail fast with a friendly error if missing

### Wrapper pattern (no re-implementation)
The Identity toolkit exposes its own public functions (e.g., `Invoke-SATADSnapshot`) that:
1. Validate profile/consent/credentials
2. Call Migration.Toolkit AD functions
3. Normalize outputs to stable CSV/JSON schemas
4. Log command + version metadata

### Suggested integration map
Identity.Security.Assessment.Toolkit public cmdlets → Migration.Toolkit exported cmdlets
- `Invoke-SATADSnapshot` → Migration Toolkit AD discovery & inventory cmdlets
- `Invoke-SATDiscovery` (AD portion) → Migration Toolkit AD discovery cmdlets
- `Invoke-SATPackageEvidence` → consumes artifacts produced by Migration.Toolkit and re-exports as normalized evidence

### Output normalization boundary
Keep Migration.Toolkit outputs untouched in a raw folder, then normalize:
output/
	<AssessmentName>_<Timestamp>/
		raw/migration-toolkit/
		ad/
		findings/

### Versioning and compatibility
- Pin a minimum Migration.Toolkit version that provides the required AD functions
- Add a compatibility matrix in docs if multiple versions are supported
- Log the exact Migration.Toolkit version used per assessment

## Identity Security Assessment — Client Environment Prerequisites
This document describes the minimum requirements to perform an Identity Security Assessment covering:
- On-premises Active Directory (AD)
- Microsoft Entra ID
- Microsoft 365 (optional, if in scope)

The assessment is designed to be read-only by default, with no configuration changes and no agent installs on domain controllers.

### 1) Execution model (recommended)
Customer-hosted assessment workstation / VM (recommended)
- Provide one dedicated Windows workstation or VM used solely for assessment activities.

Recommended characteristics
- Joined to the customer Active Directory domain
- Network access to domain controllers (standard AD management access)
- Internet access to Microsoft 365 endpoints (or approved proxy access)
- Temporary asset that can be decommissioned after the assessment

Not required
- Installing tools on domain controllers
- Installing agents on endpoints or servers

### 2) Operating system & runtime requirements
Supported operating systems
- Windows Server 2019 / 2022, or
- Windows 10/11 (Enterprise preferred)

PowerShell
- Windows PowerShell 5.1 (required)
- PowerShell 7.x (recommended)

### 3) Required software (baseline)
AD management components (required for AD scope)
- RSAT: Active Directory PowerShell module

Used for
- Domain/forest metadata
- Users, groups, computers, OUs
- Group memberships and security descriptors (ACLs)
- Password policy configuration (default and fine-grained)

Microsoft Entra ID / M365 components (required for cloud scope)
- Microsoft Graph PowerShell SDK

Used for
- Entra tenant posture (users, groups, roles, devices)
- Conditional Access policy inventory
- Authentication posture (MFA coverage indicators)
- Guest user inventory
- Application registrations and permissions inventory (read-only)

### 4) Optional software (if included in scope)
Active Directory relationship analysis (recommended for enterprise)
- SharpHound (collector)
- BloodHound Community Edition (viewer/analysis)

Notes
- Collection is read-only and gathers directory relationship metadata.
- No password attacks, exploitation, or changes are performed.

Microsoft 365 workload modules (only if workloads are in scope)
- Exchange Online: ExchangeOnlineManagement
- SharePoint/OneDrive: PnP.PowerShell
- Teams: MicrosoftTeams

Network discovery module (only if discovery is in scope)
- Nmap
- Npcap (required by Nmap on Windows)

Web scanning module (only if web scanning is in scope)
- OWASP ZAP (requires Java 11+)
- testssl.sh (requires OpenSSL)

### 5) Permissions & access requirements
On-premises Active Directory
Baseline (minimum)
- Domain account with read access to directory objects (typical domain user read access)

Recommended
- Read access to Group Policy Objects and OU security descriptors (ACLs)
- If permission boundaries restrict GPO/ACL reads, an alternate read-only account may be provided

Not required for standard assessment
- Domain Admin
- Enterprise Admin

Microsoft Entra ID / Microsoft 365
Baseline (minimum)
- Graph read permissions to directory and policy data

Recommended roles
- Global Reader and/or Security Reader

Not required for standard assessment
- Global Administrator

### 6) Network & connectivity requirements
On-premises AD connectivity
- DNS resolution for domain controllers
- LDAP/LDAPS connectivity to domain controllers (standard for directory read operations)

Microsoft 365 connectivity
- Access to Microsoft Graph endpoints (direct or via approved proxy)
- Ability to authenticate interactively (or via approved device code flow)

### 7) Data handling & operational notes
Data location
- Evidence files (CSV/JSON/logs) are generated on the assessment workstation/VM.
- Data export outside the environment occurs only with explicit customer approval.

Impact
- Read-only queries are used by default.
- Optional deep modules may increase query volume; these are enabled only by agreement and profile selection.

Decommissioning
- At completion, the customer may archive evidence and remove the workstation/VM.
- Credentials used for assessment may be disabled or removed per customer policy.

### 8) Pre-assessment validation
A validation script is available to confirm required components are installed and accessible:
- tools/Test-Prereqs.ps1

This script checks
- PowerShell version
- RSAT AD module availability
- Graph SDK availability
- Domain connectivity
- Ability to obtain a Graph access token (and optional permission checks)
