# M365 Discovery Collector Auth Architecture and Permission Matrix

## Purpose
Define the auth model and app registration strategy for Phase 3+ collection:
- Entra ID discovery (`Entra_RoleAssignments`, `Entra_ConditionalAccessPolicies`, `Entra_AuthMethods`, `Hybrid_AADConnectConfig`)
- Future Microsoft 365 workload discovery (Exchange, OneDrive, SharePoint, Teams, M365 Groups)

This is aligned to `M365.Discovery.Collector` current structure (`Collector.Graph`, `Collector.Core`, `WorkloadCatalog`).

## Current State (Code-Aligned Snapshot)
- Auth modes in code:
  - `InteractiveDelegated`
  - `AppOnly`
- Current app-only implementation uses `client secret` + Graph `.default`.
- Current delegated implementation uses interactive public client login and delegated scopes.
- Permission detection currently evaluates `GrantedScopes` only; app-only role-claim detection is not first-class yet.


## Runtime Strategy (Final Decision)
Use a split runtime model based on workload and module support:

1. AD discovery (on-prem AD DS):
- Runtime: `Windows PowerShell 5.1`
- Why: best compatibility for AD DS and GroupPolicy cmdlets on Windows servers where discovery is executed.

2. Entra + Microsoft 365 discovery:
- Runtime: `PowerShell 7.x` (preferred default)
- Why: modern auth/library support, cross-platform automation options, better long-term support posture.

3. Exception rule:
- If a required workload API/module is not stable in PS7 for a specific customer environment, document the exception and pin that collector to the supported runtime explicitly.

4. Execution boundary:
- Keep AD and Entra/M365 collection paths logically separate so each can run in its native runtime without mixed-session side effects.

## Recommended Auth Model
Use dual-mode auth with explicit workload targeting:

1. `Delegated (interactive)`:
- Best for onboarding, troubleshooting, least blast radius in early tenant engagements.
- Useful when customer wants operator-visible consent and user-context access.

2. `App-only (certificate)`:
- Primary for repeatable discovery runs and scale.
- Required for unattended execution.
- Preferred for most Entra and M365 inventory/report collection.

## App Registration Strategy (Decision)
Use **two app registrations** per tenant engagement (recommended baseline).

### App A: `CTK-M365-Collector-Delegated`
- Type: Public client app
- Auth: Interactive delegated
- No client secret/cert
- Redirect URI: `http://localhost`
- Use case: analyst-run/manual discovery and consent bootstrap

### App B: `CTK-M365-Collector-Automation`
- Type: Confidential client app
- Auth: App-only with certificate (preferred), secret only for short-term lab use
- Use case: scheduled/repeatable production discovery

### Optional App C: `CTK-M365-Collector-ExchangeElevated` (only if needed)
- Separate when Exchange app permissions/roles require tighter governance boundaries.
- Keeps high-privileged Exchange controls isolated from core Graph discovery.

## Permission Matrix (Minimum Viable by Workload)
`Mode` indicates preferred collection mode for production.

| Dataset / Capability | Collector Workload Key | Primary API | Delegated (min) | App-only (min) | Mode | Notes |
|---|---|---|---|---|---|---|
| Entra role assignments | `entra.roles` | Graph `/directoryRoles`, role assignments | `RoleManagement.Read.Directory` (or `Directory.Read.All`) | `RoleManagement.Read.Directory` (or `Directory.Read.All`) | App-only | Supports `Entra_RoleAssignments` |
| Conditional Access policies | `entra.conditionalAccess` | Graph `/identity/conditionalAccess/*` | `Policy.Read.All` | `Policy.Read.All` | App-only | Supports `Entra_ConditionalAccessPolicies` |
| Auth methods coverage | (new collector, likely `entra.authMethods`) | Graph `/reports/authenticationMethods/userRegistrationDetails` | `Reports.Read.All` + `User.Read.All` | `Reports.Read.All` + `User.Read.All` | App-only | Supports `Entra_AuthMethods` |
| Hybrid AAD Connect config | (new collector, likely `hybrid.aadConnectConfig`) | Graph `/onPremisesSynchronization/*` + org settings | `OnPremDirectorySynchronization.Read.All` + `Organization.Read.All` | `OnPremDirectorySynchronization.Read.All` + `Organization.Read.All` | App-only | Supports `Hybrid_AADConnectConfig` |
| Entra users | `entra.users` | Graph `/users` | `User.Read.All` | `User.Read.All` | App-only | Existing |
| Entra groups / M365 groups | `entra.groups`, `m365.groups` | Graph `/groups` | `Group.Read.All` | `Group.Read.All` | App-only | Existing |
| Applications / service principals | `entra.applications`, `entra.servicePrincipals` | Graph `/applications`, `/servicePrincipals` | `Application.Read.All` | `Application.Read.All` | App-only | Existing |
| Sign-in signals | `entra.signInSignals` | Graph `/auditLogs/signIns` | `AuditLog.Read.All` | `AuditLog.Read.All` | App-only | Existing collector key |
| OneDrive usage | `usage.onedrive` | Graph Reports | `Reports.Read.All` | `Reports.Read.All` | App-only | Existing |
| SharePoint usage | `usage.sharepoint` | Graph Reports | `Reports.Read.All` | `Reports.Read.All` | App-only | Existing |
| Teams activity | `usage.teams` | Graph Reports | `Reports.Read.All` | `Reports.Read.All` | App-only | Existing |
| Exchange mailbox usage (report) | `usage.exchange` | Graph Reports | `Reports.Read.All` | `Reports.Read.All` | App-only | Existing; this is report-level, not mailbox content |
| Exchange deep config (future) | (future exo collectors) | EXO PowerShell/REST | n/a (module/user context) | `Exchange.ManageAsApp` + EXO RBAC role | App-only (isolated app) | Use optional App C if deep EXO scope required |

## Consent Profiles
Apply permissions in staged bundles:

1. `Core-Entra-Phase3`:
- `RoleManagement.Read.Directory`
- `Policy.Read.All`
- `User.Read.All`
- `Group.Read.All`
- `Application.Read.All`
- `Directory.Read.All` (optional simplifier if customer prefers fewer granular grants)

2. `Core-M365-Reports`:
- `Reports.Read.All`
- `Organization.Read.All`
- `Domain.Read.All`

3. `Hybrid-Connect`:
- `OnPremDirectorySynchronization.Read.All`

4. `Exchange-Deep` (optional future):
- `Exchange.ManageAsApp` plus minimal EXO RBAC assignment

## Architectural Rules
1. Keep auth provider-agnostic collector interfaces:
- Collectors request capability keys, not direct token internals.

2. Add explicit token capability detection for both:
- Delegated scopes (`scp`)
- App roles (`roles`)

3. Enforce least privilege by workload selection:
- Only request permissions required for selected workload keys.

4. Separate “reports-only” from “directory-read” runs when possible:
- Reduces consent friction and blast radius.

## Required Code Changes (Before Phase 3 Coding)
1. `Collector.Graph/AuthConfig.cs`
- Add certificate auth fields:
  - `CertificateThumbprint`
  - `CertificateSubjectName` (optional)
  - `UseManagedIdentity` (optional future)
- Keep secret support for labs only.

2. `Collector.Graph/Auth/GraphClientFactory.cs`
- Add app-only certificate flow:
  - `WithCertificate(...)` for confidential client.
- Keep secret fallback behind explicit config flag.

3. `Collector.Graph/TokenInfo.cs` + `PermissionDetector.cs`
- Parse both `scp` and `roles`.
- Build capability matrix from union of delegated scopes and app roles.
- Label capabilities with source (`delegated`, `application`) for diagnostics.

4. `Collector.App/Services/AppRegistrationService.cs`
- Support adding both delegated `Scope` and app `Role` permissions.
- Output admin consent URL per app and per profile.

5. Preflight/UX
- Show per-workload:
  - Available / Partial / Blocked
  - Missing permission(s)
  - Missing admin consent vs token mode mismatch

## Concrete Implementation Tasks
Use this as the execution backlog for Phase 3 auth/runtime implementation.

### Sprint A: Auth Foundation
1. `A1 - AuthConfig certificate model`
- Scope:
  - Update `Collector.Graph/AuthConfig.cs` with:
    - `CertificateThumbprint`
    - `CertificateSubjectName` (optional)
    - `AllowClientSecretFallback` (bool, default `false`)
  - Add validation logic for mutually exclusive secret/certificate settings.
- Acceptance criteria:
  - Config loads with delegated mode unchanged.
  - App-only mode accepts certificate settings.
  - Secret auth works only when `AllowClientSecretFallback=true`.

2. `A2 - Graph client certificate flow`
- Scope:
  - Update `Collector.Graph/Auth/GraphClientFactory.cs`:
    - App-only path first attempts cert auth (`WithCertificate(...)`).
    - Secret path is explicit fallback only.
  - Add structured log for selected auth path.
- Acceptance criteria:
  - App-only + valid certificate acquires token successfully.
  - App-only + missing cert fails fast with actionable error.
  - App-only + secret works only when fallback flag is enabled.

3. `A3 - Token capability model (scp + roles)`
- Scope:
  - Update `Collector.Graph/TokenInfo.cs` to carry:
    - Delegated scopes (`scp`)
    - App roles (`roles`)
    - Unified `GrantedPermissions`
  - Update `Collector.Graph/PermissionDetector.cs` to evaluate both claims.
- Acceptance criteria:
  - Delegated token maps permissions from `scp`.
  - App-only token maps permissions from `roles`.
  - Diagnostics identify claim source (`delegated` vs `application`).

### Sprint B: Consent + Preflight UX
1. `B1 - App registration service role support`
- Scope:
  - Update `Collector.App/Services/AppRegistrationService.cs` to request:
    - Delegated scopes for delegated app.
    - Application roles for automation app.
  - Emit consent URL/output grouped by profile:
    - `Core-Entra-Phase3`
    - `Core-M365-Reports`
    - `Hybrid-Connect`
- Acceptance criteria:
  - Service can produce app-specific consent instructions.
  - Output clearly differentiates delegated vs application permissions.

2. `B2 - Preflight permission evaluation`
- Scope:
  - Update preflight checks to show per workload:
    - `Available`
    - `Partial`
    - `Blocked`
  - Add reason classification:
    - Missing permission
    - Wrong auth mode
    - Consent not granted
- Acceptance criteria:
  - Selecting workloads yields deterministic preflight status.
  - Missing permissions are listed explicitly.
  - Wrong-mode issues are surfaced as mode mismatch.

3. `B3 - Runtime policy preflight`
- Scope:
  - Add runtime checks:
    - AD workload requires `Windows PowerShell 5.1`.
    - Entra/M365 workload targets `PowerShell 7.x`.
  - Add explicit warning when running a workload under non-preferred runtime.
- Acceptance criteria:
  - AD run on PS7 surfaces policy warning/error (configurable behavior).
  - Entra/M365 run on PS5.1 surfaces non-supported warning/error.

### Sprint C: Workload Wiring for Phase 3 Datasets
1. `C1 - Entra role assignments collector`
- Scope:
  - Implement collector key `entra.roles`.
  - Export mapped schema for `Entra_RoleAssignments`.
- Acceptance criteria:
  - Output produced with app-only permissions from matrix.

2. `C2 - Conditional Access collector`
- Scope:
  - Implement collector key `entra.conditionalAccess`.
  - Export mapped schema for `Entra_ConditionalAccessPolicies`.
- Acceptance criteria:
  - Policies and controls are exported consistently.

3. `C3 - Auth methods coverage collector`
- Scope:
  - Implement collector key `entra.authMethods`.
  - Export mapped schema for `Entra_AuthMethods`.
- Acceptance criteria:
  - User registration coverage output generated.

4. `C4 - Hybrid AAD Connect config collector`
- Scope:
  - Implement collector key `hybrid.aadConnectConfig`.
  - Export mapped schema for `Hybrid_AADConnectConfig`.
- Acceptance criteria:
  - Sync-related configuration signals are exported.

### Sprint D: Validation + Hardening
1. `D1 - Contract tests for permission detection`
- Scope:
  - Add tests with synthetic delegated/app-only token claims.
- Acceptance criteria:
  - Tests prove same capability can be satisfied by `scp` or `roles`.

2. `D2 - Integration smoke tests`
- Scope:
  - Test both auth apps against a lab tenant:
    - delegated interactive
    - app-only certificate
  - Verify each Phase 3 dataset can be collected when expected permissions are present.
- Acceptance criteria:
  - Smoke run outputs expected CSV/artifacts.
  - Preflight statuses match observed behavior.

3. `D3 - Operational runbook`
- Scope:
  - Document app creation, consent, cert install, rotation, and troubleshooting.
- Acceptance criteria:
  - New operator can onboard tenant and run discovery without code changes.

## Operational Guidance
- Runtime policy: AD collectors run in Windows PowerShell 5.1; Entra/M365 collectors run in PowerShell 7.x unless a documented compatibility exception exists.
- Production: certificate auth only for app-only (no long-lived client secrets).
- Store cert private key in:
  - Windows cert store (service account context), or
  - Key Vault (if/when moving to hosted automation).
- Rotate certs on defined cadence (6-12 months recommended).
- Persist run metadata including:
  - auth mode
  - app id
  - tenant id
  - granted permissions seen in token

## Go/No-Go Decision for Phase 3
Proceed with Phase 3 coding after confirming:
1. Two app registrations approved (`Delegated`, `Automation`).
2. `Core-Entra-Phase3` and `Core-M365-Reports` consent granted.
3. Certificate selected and available for automation app.
4. PermissionDetector updated to support app roles (not just delegated scopes).
