// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
namespace Collector.Core.Analysis;

public sealed class MigrationRiskAnalyzer
{
    public static MigrationRiskReport AnalyzeRisks(IEnumerable<CollectorResult> results)
    {
        var report = new MigrationRiskReport();
        List<Collectors.ConditionalAccessPolicyRecord>? conditionalAccess = null;
        List<Collectors.AuthMethodCoverageRecord>? authMethods = null;
        List<Collectors.HybridAadConnectConfigRecord>? hybridConfig = null;
        List<Collectors.EntraRoleRecord>? roles = null;
        var hasAuthoritativeHybridConfig = false;

        foreach (var result in results)
        {
            if (!result.Success || result.Data == null)
                continue;

            switch (result.WorkloadKey)
            {
                case "entra.conditionalAccess":
                    conditionalAccess = ((IEnumerable<Collectors.ConditionalAccessPolicyRecord>)result.Data).ToList();
                    AnalyzeConditionalAccessRisks(result.Data, report);
                    break;
                case "entra.guests":
                    AnalyzeGuestRisks(result.Data, report);
                    break;
                case "entra.appCredentials":
                    AnalyzeCredentialRisks(result.Data, report);
                    break;
                case "entra.groupInventoryPlus":
                    AnalyzeGroupRisks(result.Data, report);
                    break;
                case "entra.authMethods":
                    authMethods = ((IEnumerable<Collectors.AuthMethodCoverageRecord>)result.Data).ToList();
                    AnalyzeAuthMethodsRisks(result.Data, report);
                    break;
                case "hybrid.aadConnectConfig":
                    hybridConfig = ((IEnumerable<Collectors.HybridAadConnectConfigRecord>)result.Data).ToList();
                    hasAuthoritativeHybridConfig = result.ConfidenceLevel == ConfidenceLevel.Authoritative;
                    AnalyzeHybridAadConnectRisks(result.Data, report);
                    break;
                case "entra.roles":
                    roles = ((IEnumerable<Collectors.EntraRoleRecord>)result.Data).ToList();
                    AnalyzeRoleAssignmentRisks(result.Data, report);
                    break;
            }
        }

        AnalyzePhase3ControlPlaneRisks(roles, conditionalAccess, authMethods, hybridConfig, hasAuthoritativeHybridConfig, report);

        return report;
    }

    private static void AnalyzeConditionalAccessRisks(object data, MigrationRiskReport report)
    {
        var policies = (IEnumerable<Collectors.ConditionalAccessPolicyRecord>)data;
        
        var enabledPolicies = policies.Where(p => p.State == "enabled").ToList();
        var policiesWithGroups = enabledPolicies.Where(p => p.IncludedGroupCount > 0 || p.ExcludedGroupCount > 0).ToList();
        var policiesWithNamedLocations = enabledPolicies.Where(p => p.HasNamedLocations).ToList();
        var mfaPolicies = enabledPolicies.Where(p => p.RequireMultiFactor).ToList();
        var allUsersMfaPolicies = mfaPolicies.Where(p => p.IncludeAllUsers).ToList();

        if (!enabledPolicies.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Critical,
                Category: "Conditional Access",
                Title: "No enabled Conditional Access policies",
                Description: "No enabled Conditional Access policies were detected, leaving sign-in controls weak for migration and steady state.",
                Recommendation: "Establish and validate a baseline Conditional Access policy set for ongoing tenant security.",
                AffectedCount: 0
            ));
            return;
        }

        if (!allUsersMfaPolicies.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.High,
                Category: "Conditional Access",
                Title: "No enabled all-users MFA Conditional Access policy",
                Description: "Enabled CA policies exist, but none enforce MFA for all users; privileged and high-value accounts may remain under-protected.",
                Recommendation: "Create and validate an enabled baseline MFA CA policy covering all users or all privileged roles for steady-state protection.",
                AffectedCount: mfaPolicies.Count
            ));
        }

        if (policiesWithGroups.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Critical,
                Category: "Conditional Access",
                Title: $"{policiesWithGroups.Count} CA policies reference groups",
                Description: "Conditional Access policies with group assignments will break if source groups are not migrated or mapped",
                Recommendation: "Maintain documented group mappings and change-control validation before enabling or modifying CA policies",
                AffectedCount: policiesWithGroups.Count
            ));
        }

        if (policiesWithNamedLocations.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.High,
                Category: "Conditional Access",
                Title: $"{policiesWithNamedLocations.Count} CA policies use named locations",
                Description: "Named locations must be recreated in target tenant before migration",
                Recommendation: "Document and validate named location configurations and keep them synchronized with policy intent",
                AffectedCount: policiesWithNamedLocations.Count
            ));
        }
    }

    private static void AnalyzeGuestRisks(object data, MigrationRiskReport report)
    {
        var guests = (IEnumerable<Collectors.GuestUserRecord>)data;
        
        var orphanedGuests = guests.Where(g => g.IsOrphaned).ToList();
        var pendingGuests = guests.Where(g => g.IsPendingAcceptance).ToList();

        if (orphanedGuests.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Medium,
                Category: "Guest Users",
                Title: $"{orphanedGuests.Count} orphaned guest users",
                Description: "Guest users with no group memberships - may indicate stale accounts",
                Recommendation: "Review and clean up orphaned guests as part of periodic identity governance",
                AffectedCount: orphanedGuests.Count
            ));
        }

        if (pendingGuests.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Low,
                Category: "Guest Users",
                Title: $"{pendingGuests.Count} pending guest invitations",
                Description: "Guest invitations not yet accepted",
                Recommendation: "Complete or cancel pending invitations promptly to reduce stale external access",
                AffectedCount: pendingGuests.Count
            ));
        }
    }

    private static void AnalyzeCredentialRisks(object data, MigrationRiskReport report)
    {
        var credentials = (IEnumerable<Collectors.AppCredentialRecord>)data;
        
        var expiringSoon = credentials.Where(c => c.IsExpiringSoon).ToList();
        var expired = credentials.Where(c => c.IsExpired).ToList();

        if (expiringSoon.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Critical,
                Category: "App Credentials",
                Title: $"{expiringSoon.Count} credentials expiring within 90 days",
                Description: "App secrets/certificates expiring during typical migration window",
                Recommendation: "Implement proactive credential rotation and expiration monitoring for application identities",
                AffectedCount: expiringSoon.Count
            ));
        }

        if (expired.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.High,
                Category: "App Credentials",
                Title: $"{expired.Count} expired credentials",
                Description: "Already-expired credentials indicate potentially broken apps",
                Recommendation: "Investigate and renew expired credentials",
                AffectedCount: expired.Count
            ));
        }
    }

    private static void AnalyzeGroupRisks(object data, MigrationRiskReport report)
    {
        var groups = (IEnumerable<Collectors.GroupInventoryRecord>)data;
        
        var orphaned = groups.Where(g => g.IsOrphaned).ToList();
        var largeGroups = groups.Where(g => g.IsLargeGroup).ToList();

        if (orphaned.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Medium,
                Category: "Groups",
                Title: $"{orphaned.Count} orphaned groups (no owners)",
                Description: "Groups without owners create governance and migration challenges",
                Recommendation: "Assign accountable owners to all groups and enforce ownership reviews",
                AffectedCount: orphaned.Count
            ));
        }

        if (largeGroups.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Medium,
                Category: "Groups",
                Title: $"{largeGroups.Count} large groups (>1000 members)",
                Description: "Large groups may cause performance issues during migration validation",
                Recommendation: "Apply additional operational validation and governance controls for large groups",
                AffectedCount: largeGroups.Count
            ));
        }
    }

    private static void AnalyzeAuthMethodsRisks(object data, MigrationRiskReport report)
    {
        var records = (IEnumerable<Collectors.AuthMethodCoverageRecord>)data;
        var rows = records.ToList();
        if (rows.Count == 0)
        {
            return;
        }

        var adminsWithoutMfa = rows
            .Where(r => r.IsAdmin == true && (r.IsMfaRegistered != true || r.IsMfaCapable != true))
            .ToList();
        var usersWithoutMethods = rows
            .Where(r => r.MethodsRegisteredCount == 0)
            .ToList();

        if (adminsWithoutMfa.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Critical,
                Category: "Auth Methods",
                Title: $"{adminsWithoutMfa.Count} admin account(s) without full MFA registration",
                Description: "Privileged users lacking MFA registration/capability materially increase identity takeover risk during migration.",
                Recommendation: "Require MFA registration for all privileged users as a baseline control.",
                AffectedCount: adminsWithoutMfa.Count
            ));
        }

        if (usersWithoutMethods.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Medium,
                Category: "Auth Methods",
                Title: $"{usersWithoutMethods.Count} user(s) with no registered auth methods",
                Description: "Users without registered methods can increase helpdesk load and sign-in failures post-migration.",
                Recommendation: "Run ongoing preregistration campaigns for MFA/SSPR methods to reduce user risk and support load.",
                AffectedCount: usersWithoutMethods.Count
            ));
        }
    }

    private static void AnalyzeHybridAadConnectRisks(object data, MigrationRiskReport report)
    {
        var records = (IEnumerable<Collectors.HybridAadConnectConfigRecord>)data;
        var row = records.FirstOrDefault();
        if (row == null)
        {
            return;
        }

        if (row.OnPremisesSyncEnabled == true && row.HasOnPremisesSynchronizationConfig != true)
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.High,
                Category: "Hybrid Identity",
                Title: "Hybrid sync enabled but on-prem sync configuration unavailable",
                Description: "Directory synchronization is enabled, but configuration details were not retrievable. This limits migration planning confidence.",
                Recommendation: "Validate app-only access and OnPremDirectorySynchronization.Read.All consent to ensure continuous hybrid visibility.",
                AffectedCount: 1
            ));
        }

        if (row.OnPremisesSyncEnabled == true && string.IsNullOrWhiteSpace(row.SyncConfigurationVersion))
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Medium,
                Category: "Hybrid Identity",
                Title: "Hybrid sync configuration version not captured",
                Description: "Missing sync configuration version reduces ability to validate Entra Connect posture.",
                Recommendation: "Confirm sync endpoint access and capture Hybrid_AADConnectConfig as part of hybrid security baselining.",
                AffectedCount: 1
            ));
        }
    }

    private static void AnalyzeRoleAssignmentRisks(object data, MigrationRiskReport report)
    {
        var roles = ((IEnumerable<Collectors.EntraRoleRecord>)data).ToList();
        if (roles.Count == 0)
        {
            return;
        }

        var globalAdmins = roles.FirstOrDefault(r =>
            string.Equals(r.DisplayName, "Global Administrator", StringComparison.OrdinalIgnoreCase));

        if (globalAdmins != null && globalAdmins.IsActivated && globalAdmins.MemberCount < 2)
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.High,
                Category: "Role Assignments",
                Title: "Fewer than 2 Global Administrators are activated",
                Description: "Single-admin dependency increases operational and lockout risk during migration activities.",
                Recommendation: "Maintain at least two emergency-access Global Administrator accounts with tested controls.",
                AffectedCount: globalAdmins.MemberCount
            ));
        }

        if (globalAdmins != null && globalAdmins.IsActivated && globalAdmins.MemberCount > 5)
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.High,
                Category: "Role Assignments",
                Title: $"{globalAdmins.MemberCount} Global Administrators assigned",
                Description: "Excessive Global Administrator assignments increase blast radius and migration change risk.",
                Recommendation: "Reduce standing Global Administrator assignments and prefer least-privilege role delegation.",
                AffectedCount: globalAdmins.MemberCount
            ));
        }

        // Uses role assignment counts (not de-duplicated principals) as a practical risk signal.
        var privilegedRoleNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Global Administrator",
            "Privileged Role Administrator",
            "Security Administrator",
            "Conditional Access Administrator",
            "Exchange Administrator",
            "SharePoint Administrator",
            "User Administrator",
            "Cloud Application Administrator",
            "Application Administrator",
            "Authentication Administrator",
            "Helpdesk Administrator"
        };

        var privilegedAssignments = roles
            .Where(r => r.IsActivated && r.MemberCount > 0 && !string.IsNullOrWhiteSpace(r.DisplayName))
            .Where(r => privilegedRoleNames.Contains(r.DisplayName!))
            .Sum(r => r.MemberCount);

        if (privilegedAssignments > 10)
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Medium,
                Category: "Role Assignments",
                Title: $"{privilegedAssignments} privileged role assignments detected",
                Description: "High volume of privileged role assignments raises governance complexity and migration control-plane risk.",
                Recommendation: "Review privileged role assignments regularly and reduce standing access using least-privilege principles.",
                AffectedCount: privilegedAssignments
            ));
        }
    }

    private static void AnalyzePhase3ControlPlaneRisks(
        List<Collectors.EntraRoleRecord>? roles,
        List<Collectors.ConditionalAccessPolicyRecord>? conditionalAccess,
        List<Collectors.AuthMethodCoverageRecord>? authMethods,
        List<Collectors.HybridAadConnectConfigRecord>? hybridConfig,
        bool hasAuthoritativeHybridConfig,
        MigrationRiskReport report)
    {
        if (roles == null || conditionalAccess == null || authMethods == null)
        {
            return;
        }

        var globalAdmins = roles.FirstOrDefault(r =>
            string.Equals(r.DisplayName, "Global Administrator", StringComparison.OrdinalIgnoreCase));
        var gaCount = (globalAdmins?.IsActivated == true) ? globalAdmins.MemberCount : 0;

        var adminsWithoutMfa = authMethods.Count(r =>
            r.IsAdmin == true && (r.IsMfaRegistered != true || r.IsMfaCapable != true));

        var hasEnabledMfaPolicy = conditionalAccess.Any(p =>
            string.Equals(p.State, "enabled", StringComparison.OrdinalIgnoreCase) &&
            p.RequireMultiFactor &&
            p.IncludeAllUsers);

        if (gaCount > 0 && adminsWithoutMfa > 0 && !hasEnabledMfaPolicy)
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Critical,
                Category: "Identity Control Plane",
                Title: "Privileged admin MFA gap with no universal CA MFA enforcement",
                Description: "Global admin presence plus admin MFA gaps without an enabled all-users MFA CA policy is a high-risk migration posture.",
                Recommendation: "Enforce MFA for all users (or at minimum privileged roles) in Conditional Access as a baseline security control.",
                AffectedCount: adminsWithoutMfa
            ));
        }

        var hybrid = hybridConfig?.FirstOrDefault();
        if (hasAuthoritativeHybridConfig &&
            hybrid?.OnPremisesSyncEnabled == true &&
            hybrid.HasOnPremisesSynchronizationConfig == true &&
            !hasEnabledMfaPolicy)
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.High,
                Category: "Hybrid Security",
                Title: "Hybrid sync enabled without universal CA MFA policy",
                Description: "Hybrid identities increase attack surface; missing broad MFA enforcement elevates account takeover risk.",
                Recommendation: "Enable and validate a CA MFA baseline for hybrid identity security operations.",
                AffectedCount: 1
            ));
        }
    }
}

public sealed class MigrationRiskReport
{
    public List<RiskItem> Risks { get; } = new();
    public DateTimeOffset GeneratedAt { get; } = DateTimeOffset.UtcNow;

    public void AddRisk(RiskItem risk) => Risks.Add(risk);

    public int CriticalRisks => Risks.Count(r => r.Severity == RiskSeverity.Critical);
    public int HighRisks => Risks.Count(r => r.Severity == RiskSeverity.High);
    public int MediumRisks => Risks.Count(r => r.Severity == RiskSeverity.Medium);
    public int LowRisks => Risks.Count(r => r.Severity == RiskSeverity.Low);
}

public sealed record RiskItem(
    RiskSeverity Severity,
    string Category,
    string Title,
    string Description,
    string Recommendation,
    int AffectedCount
);

public enum RiskSeverity
{
    Low,
    Medium,
    High,
    Critical
}
