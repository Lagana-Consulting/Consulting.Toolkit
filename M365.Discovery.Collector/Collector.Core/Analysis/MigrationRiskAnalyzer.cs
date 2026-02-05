namespace Collector.Core.Analysis;

public sealed class MigrationRiskAnalyzer
{
    public static MigrationRiskReport AnalyzeRisks(IEnumerable<CollectorResult> results)
    {
        var report = new MigrationRiskReport();

        foreach (var result in results)
        {
            if (!result.Success || result.Data == null)
                continue;

            switch (result.WorkloadKey)
            {
                case "entra.conditionalAccess":
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
            }
        }

        return report;
    }

    private static void AnalyzeConditionalAccessRisks(object data, MigrationRiskReport report)
    {
        var policies = (IEnumerable<Collectors.ConditionalAccessPolicyRecord>)data;
        
        var enabledPolicies = policies.Where(p => p.State == "enabled").ToList();
        var policiesWithGroups = enabledPolicies.Where(p => p.IncludedGroupCount > 0 || p.ExcludedGroupCount > 0).ToList();
        var policiesWithNamedLocations = enabledPolicies.Where(p => p.HasNamedLocations).ToList();

        if (policiesWithGroups.Any())
        {
            report.AddRisk(new RiskItem(
                Severity: RiskSeverity.Critical,
                Category: "Conditional Access",
                Title: $"{policiesWithGroups.Count} CA policies reference groups",
                Description: "Conditional Access policies with group assignments will break if source groups are not migrated or mapped",
                Recommendation: "Map source groups to target groups before enabling CA policies in target tenant",
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
                Recommendation: "Export and recreate all named location configurations",
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
                Recommendation: "Review and cleanup orphaned guests before migration",
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
                Recommendation: "Complete or cancel pending invitations before migration",
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
                Recommendation: "Renew credentials before migration or plan for rotation during migration",
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
                Recommendation: "Assign owners to all groups before migration",
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
                Recommendation: "Plan additional validation time for large groups",
                AffectedCount: largeGroups.Count
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