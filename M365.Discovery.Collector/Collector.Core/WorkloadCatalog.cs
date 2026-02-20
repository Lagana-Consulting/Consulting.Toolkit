namespace Collector.Core;

public sealed record WorkloadDefinition(
    string Key,
    string DisplayName,
    string Description,
    bool IsDefaultSelected,
    string[] RequiredPermissions,
    string Category = "General"
);

public sealed class WorkloadCatalog
{
    public List<WorkloadDefinition> Workloads { get; } = new();

    public static WorkloadCatalog CreateDefault()
    {
        var catalog = new WorkloadCatalog();

        // ===== ENTRA ID =====
        // Core identity objects
        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.users",
            "Users",
            "User accounts, licenses, assignments",
            true,
            new[] { "User.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.groups",
            "Groups",
            "Security & distribution groups",
            true,
            new[] { "Group.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.applications",
            "Application Registrations",
            "App registrations & API permissions",
            true,
            new[] { "Application.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.servicePrincipals",
            "Service Principals",
            "Enterprise apps & service principals",
            true,
            new[] { "Application.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.roles",
            "Directory Roles",
            "Admin roles & assignments",
            true,
            new[] { "Directory.Read.All" },
            "Entra ID"
        ));

        // Access & policy management
        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.conditionalAccess",
            "Conditional Access Policies",
            "CA policies, assignments, controls & named locations",
            true,
            new[] { "Policy.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.crossTenantAccess",
            "Cross-Tenant Access",
            "B2B collaboration & tenant restrictions",
            true,
            new[] { "Policy.Read.All", "Directory.Read.All" },
            "Entra ID"
        ));

        // User analysis
        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.guests",
            "Guest Users",
            "External users & collaboration analysis",
            true,
            new[] { "User.Read.All", "Group.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.signInSignals",
            "Sign-In Activity",
            "Last sign-in dates & user activity patterns",
            false,
            new[] { "AuditLog.Read.All", "User.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.authMethods",
            "Auth Methods Coverage",
            "MFA/SSPR/passwordless registration coverage by user",
            false,
            new[] { "Reports.Read.All", "User.Read.All" },
            "Entra ID"
        ));

        // Group analysis
        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.groupInventoryPlus",
            "Group Details",
            "Group owners, member counts & governance",
            true,
            new[] { "Group.Read.All" },
            "Entra ID"
        ));

        // App management
        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.appCredentials",
            "App Credentials",
            "App/SP secrets & certificate expiration",
            true,
            new[] { "Application.Read.All" },
            "Entra ID"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.appAssignments",
            "App Permissions",
            "Service principal role assignments",
            true,
            new[] { "Application.Read.All", "Directory.Read.All" },
            "Entra ID"
        ));

        // Directory configuration
        catalog.Workloads.Add(new WorkloadDefinition(
            "entra.directorySettings",
            "Directory Settings",
            "Password policies & tenant configuration",
            true,
            new[] { "Directory.Read.All" },
            "Entra ID"
        ));

        // ===== MICROSOFT 365 =====
        catalog.Workloads.Add(new WorkloadDefinition(
            "m365.groups",
            "M365 Groups",
            "Unified groups (Teams-enabled)",
            true,
            new[] { "Group.Read.All" },
            "Microsoft 365"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "usage.onedrive",
            "OneDrive Usage",
            "OneDrive activity & storage",
            false,
            new[] { "Reports.Read.All" },
            "Microsoft 365"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "usage.sharepoint",
            "SharePoint Usage",
            "Site activity & storage",
            false,
            new[] { "Reports.Read.All" },
            "Microsoft 365"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "usage.teams",
            "Teams Activity",
            "Teams usage & collaboration",
            false,
            new[] { "Reports.Read.All" },
            "Microsoft 365"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "usage.exchange",
            "Exchange Mailbox Usage",
            "Mailbox activity, storage & archive details",
            false,
            new[] { "Reports.Read.All" },
            "Microsoft 365"
        ));

        // ===== ORGANIZATION =====
        catalog.Workloads.Add(new WorkloadDefinition(
            "org.organization",
            "Organization Info",
            "Tenant details, domains, licenses",
            true,
            new[] { "Organization.Read.All" },
            "Organization"
        ));

        catalog.Workloads.Add(new WorkloadDefinition(
            "hybrid.aadConnectConfig",
            "Hybrid AAD Connect Config",
            "On-premises directory synchronization configuration signals",
            false,
            new[] { "OnPremDirectorySynchronization.Read.All", "Organization.Read.All" },
            "Organization"
        ));

        return catalog;
    }

    public string[] GetRequiredPermissionsForKeys(IEnumerable<string> workloadKeys)
    {
        return Workloads
            .Where(w => workloadKeys.Contains(w.Key))
            .SelectMany(w => w.RequiredPermissions)
            .Distinct()
            .OrderBy(p => p)
            .ToArray();
    }
}
