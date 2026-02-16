# PermissionsMatrix.md
# Permissions Matrix — Identity Security Assessment

This matrix lists the **least-privilege** permissions required for standard data collection.
“Optional” items are required only when corresponding modules are enabled.

> Notes:
> - “Role” refers to directory roles in Entra ID.
> - “Graph Permission” refers to Microsoft Graph delegated permissions (or app permissions if agreed).
> - AD permissions are described as directory read access and targeted read rights where applicable.

| Area | Data / Check | Tool / Method | Minimum Role / AD Rights | Graph Permission (Delegated) | Required? | Why Needed |
|---|---|---|---|---|---:|---|
| AD | Domain / forest summary | RSAT AD PowerShell | Domain user read | N/A | Yes | Establish baseline topology and functional levels |
| AD | DC inventory, OS versions | RSAT AD PowerShell | Domain user read | N/A | Yes | Identify outdated or unsupported platforms |
| AD | Users / groups / computers inventory | RSAT AD PowerShell | Domain user read | N/A | Yes | Counts, hygiene, and exposure baselines |
| AD | Privileged group membership (recursive) | RSAT AD PowerShell | Read group membership | N/A | Yes | Privilege creep and Tier-0 exposure |
| AD | OU delegation (ACLs) | RSAT AD PowerShell | Read security descriptors (ACL read) | N/A | Recommended | Identify risky delegation paths |
| AD | GPO inventory / links | RSAT + GPO module (if used) | Read GPOs | N/A | Optional | Identify security policy posture and drift |
| AD | Password policy (default + FGPP) | RSAT AD PowerShell | Read policy objects | N/A | Yes | Validate password standards and inconsistency |
| AD | Relationship analysis | SharpHound / BloodHound CE | Domain user read | N/A | Optional | Identify effective permissions and attack paths |
| Entra | Tenant summary | Graph SDK | Global Reader or equivalent permissions | Directory.Read.All | Yes | Baseline tenant posture |
| Entra | Users, groups, devices inventory | Graph SDK | Global Reader | User.Read.All + Group.Read.All (or Directory.Read.All) | Yes | Identity inventory and hygiene |
| Entra | Directory roles assignments | Graph SDK | Global Reader / Security Reader | RoleManagement.Read.Directory | Recommended | Evaluate privileged access |
| Entra | Conditional Access policies | Graph SDK | Security Reader / Global Reader | Policy.Read.All | Recommended | Coverage and gap analysis |
| Entra | Auth methods / MFA coverage indicators | Graph SDK | Security Reader / Global Reader | UserAuthenticationMethod.Read.All | Optional | Determine MFA coverage (requires higher access) |
| Entra | Sign-in logs (interactive/non-interactive) | Graph SDK | Security Reader | AuditLog.Read.All | Optional | Confirm legacy auth and risky sign-ins in practice |
| Entra | Audit logs | Graph SDK | Security Reader | AuditLog.Read.All | Optional | Validate admin actions and configuration change history |
| Entra | App registrations / enterprise apps | Graph SDK | Global Reader / Security Reader | Application.Read.All | Optional | Identify risky app permissions and consent patterns |
| M365 | EXO posture (legacy protocols, auditing) | EXO PowerShell | Exchange View-Only / Security Reader (varies) | N/A | Optional | Mailbox and protocol risk posture |
| M365 | SPO/OD sharing posture | PnP.PowerShell | SharePoint admin read (or equivalent) | N/A | Optional | External sharing and anonymous link posture |
| M365 | Teams external access posture | Teams PowerShell | Teams admin read (or equivalent) | N/A | Optional | Guest and federation risk posture |
