namespace Collector.Graph;

public sealed class PermissionDetector
{
    private readonly TokenInfo _tokenInfo;

    public PermissionDetector(TokenInfo tokenInfo)
    {
        _tokenInfo = tokenInfo ?? throw new ArgumentNullException(nameof(tokenInfo));
    }

    /// <summary>
    /// Build capability matrix from granted delegated scopes and application roles.
    /// </summary>
    public CapabilityMatrix DetectCapabilities()
    {
        var delegated = GetDelegatedPermissions();
        var application = GetApplicationPermissions();
        var permissions = delegated
            .Concat(application)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var capabilities = new Dictionary<string, CapabilityStatus>
        {
            // WorkloadCatalog keys (current)
            ["entra.users"] = DetectEntraUsers(permissions),
            ["entra.groups"] = DetectEntraGroups(permissions),
            ["entra.applications"] = DetectEntraApps(permissions),
            ["entra.servicePrincipals"] = DetectEntraServicePrincipals(permissions),
            ["entra.roles"] = DetectEntraRoles(permissions),
            ["entra.conditionalAccess"] = DetectConditionalAccess(permissions),
            ["entra.crossTenantAccess"] = DetectCrossTenantAccess(permissions),
            ["entra.guests"] = DetectGuests(permissions),
            ["entra.signInSignals"] = DetectSignInSignals(permissions),
            ["entra.authMethods"] = DetectAuthMethods(permissions),
            ["entra.groupInventoryPlus"] = DetectEntraGroups(permissions),
            ["entra.appCredentials"] = DetectEntraApps(permissions),
            ["entra.appAssignments"] = DetectAppAssignments(permissions),
            ["entra.directorySettings"] = DetectDirectorySettings(permissions),
            ["m365.groups"] = DetectEntraGroups(permissions),
            ["usage.onedrive"] = DetectReportsOneDrive(permissions),
            ["usage.sharepoint"] = DetectReportsSharePoint(permissions),
            ["usage.teams"] = DetectReportsTeams(permissions),
            ["usage.exchange"] = DetectReportsExchange(permissions),
            ["org.organization"] = DetectOrganization(permissions),
            ["hybrid.aadConnectConfig"] = DetectHybridAadConnectConfig(permissions, _tokenInfo.AuthMode),

            // Legacy keys kept for compatibility
            ["entra.m365groups"] = DetectEntraGroups(permissions),
            ["entra.apps"] = DetectEntraApps(permissions),
            ["reports.onedrive"] = DetectReportsOneDrive(permissions),
            ["reports.sharepoint"] = DetectReportsSharePoint(permissions),
            ["reports.teams"] = DetectReportsTeams(permissions),
            ["reports.exchange"] = DetectReportsExchange(permissions),
            ["organization.basic"] = DetectOrganization(permissions),
            ["licenses.skus"] = DetectLicenses(permissions),
            ["domains.list"] = DetectDomains(permissions),
        };

        var capabilitySources = capabilities.ToDictionary(
            kvp => kvp.Key,
            kvp => DetermineCapabilitySource(kvp.Key, delegated, application),
            StringComparer.OrdinalIgnoreCase);

        var grantedPermissions = permissions.ToArray();

        return new CapabilityMatrix(capabilities, grantedPermissions, _tokenInfo.AuthMode, capabilitySources);
    }

    private HashSet<string> GetDelegatedPermissions()
    {
        if (_tokenInfo.DelegatedScopes.Length > 0)
        {
            return _tokenInfo.DelegatedScopes.ToHashSet(StringComparer.OrdinalIgnoreCase);
        }

        if (_tokenInfo.AuthMode == AuthMode.InteractiveDelegated)
        {
            return _tokenInfo.GrantedScopes.ToHashSet(StringComparer.OrdinalIgnoreCase);
        }

        return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    }

    private HashSet<string> GetApplicationPermissions()
    {
        if (_tokenInfo.ApplicationRoles.Length > 0)
        {
            return _tokenInfo.ApplicationRoles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        }

        if (_tokenInfo.AuthMode == AuthMode.AppOnly)
        {
            return _tokenInfo.GrantedScopes.ToHashSet(StringComparer.OrdinalIgnoreCase);
        }

        return new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    }

    private static CapabilityPermissionSource DetermineCapabilitySource(
        string capabilityKey,
        HashSet<string> delegated,
        HashSet<string> application)
    {
        var tokens = GetPermissionTokens(capabilityKey);
        if (tokens.Length == 0)
        {
            return CapabilityPermissionSource.Unknown;
        }

        var hasDelegated = tokens.Any(t => delegated.Contains(t));
        var hasApplication = tokens.Any(t => application.Contains(t));

        if (hasDelegated && hasApplication) return CapabilityPermissionSource.Both;
        if (hasDelegated) return CapabilityPermissionSource.Delegated;
        if (hasApplication) return CapabilityPermissionSource.Application;
        return CapabilityPermissionSource.None;
    }

    private static CapabilityStatus DetectEntraUsers(HashSet<string> permissions)
    {
        if (permissions.Contains("User.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("User.ReadBasic.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectEntraGroups(HashSet<string> permissions)
    {
        if (permissions.Contains("Group.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectEntraApps(HashSet<string> permissions)
    {
        if (permissions.Contains("Application.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectEntraServicePrincipals(HashSet<string> permissions)
    {
        if (permissions.Contains("Application.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectEntraRoles(HashSet<string> permissions)
    {
        if (permissions.Contains("RoleManagement.Read.All") ||
            permissions.Contains("RoleManagement.Read.Directory") ||
            permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectReportsOneDrive(HashSet<string> permissions)
    {
        if (permissions.Contains("Reports.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("Files.Read.All") || permissions.Contains("Sites.Read.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectReportsSharePoint(HashSet<string> permissions)
    {
        if (permissions.Contains("Reports.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("Sites.Read.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectReportsTeams(HashSet<string> permissions)
    {
        if (permissions.Contains("Reports.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectReportsExchange(HashSet<string> permissions)
    {
        if (permissions.Contains("Reports.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectOrganization(HashSet<string> permissions)
    {
        if (permissions.Contains("Organization.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectConditionalAccess(HashSet<string> permissions)
    {
        if (permissions.Contains("Policy.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectCrossTenantAccess(HashSet<string> permissions)
    {
        if (permissions.Contains("Policy.Read.All") && permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("Policy.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectGuests(HashSet<string> permissions)
    {
        if (permissions.Contains("User.Read.All") && permissions.Contains("Group.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("User.Read.All") || permissions.Contains("Group.Read.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectSignInSignals(HashSet<string> permissions)
    {
        if (permissions.Contains("AuditLog.Read.All") && permissions.Contains("User.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("AuditLog.Read.All") || permissions.Contains("User.Read.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectAuthMethods(HashSet<string> permissions)
    {
        if (permissions.Contains("Reports.Read.All") && permissions.Contains("User.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("Reports.Read.All") || permissions.Contains("User.Read.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectAppAssignments(HashSet<string> permissions)
    {
        if (permissions.Contains("Application.Read.All") && permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        if (permissions.Contains("Application.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Partial;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectDirectorySettings(HashSet<string> permissions)
    {
        if (permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectLicenses(HashSet<string> permissions)
    {
        if (permissions.Contains("Organization.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectDomains(HashSet<string> permissions)
    {
        if (permissions.Contains("Domain.Read.All") || permissions.Contains("Directory.Read.All"))
            return CapabilityStatus.Available;
        return CapabilityStatus.Blocked;
    }

    private static CapabilityStatus DetectHybridAadConnectConfig(HashSet<string> permissions, AuthMode authMode)
    {
        var hasOnPremSyncRead = permissions.Contains("OnPremDirectorySynchronization.Read.All");
        var hasOrgRead = permissions.Contains("Organization.Read.All") || permissions.Contains("Directory.Read.All");

        if (authMode == AuthMode.AppOnly)
        {
            if (hasOnPremSyncRead && hasOrgRead)
                return CapabilityStatus.Available;
        }
        else
        {
            // Delegated path additionally depends on Entra role assignment for this endpoint.
            // Without role-claim parsing here, keep this as Partial even when scopes are present.
            if (hasOnPremSyncRead && hasOrgRead)
                return CapabilityStatus.Partial;
        }

        if (hasOnPremSyncRead || hasOrgRead)
            return CapabilityStatus.Partial;

        return CapabilityStatus.Blocked;
    }

    private static string[] GetPermissionTokens(string capabilityKey)
    {
        return capabilityKey switch
        {
            "entra.users" => new[] { "User.Read.All", "Directory.Read.All", "User.ReadBasic.All" },
            "entra.groups" => new[] { "Group.Read.All", "Directory.Read.All" },
            "entra.applications" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.m365groups" => new[] { "Group.Read.All", "Directory.Read.All" },
            "entra.apps" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.servicePrincipals" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.roles" => new[] { "RoleManagement.Read.All", "RoleManagement.Read.Directory", "Directory.Read.All" },
            "entra.conditionalAccess" => new[] { "Policy.Read.All" },
            "entra.crossTenantAccess" => new[] { "Policy.Read.All", "Directory.Read.All" },
            "entra.guests" => new[] { "User.Read.All", "Group.Read.All" },
            "entra.signInSignals" => new[] { "AuditLog.Read.All", "User.Read.All" },
            "entra.authMethods" => new[] { "Reports.Read.All", "User.Read.All" },
            "entra.groupInventoryPlus" => new[] { "Group.Read.All", "Directory.Read.All" },
            "entra.appCredentials" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.appAssignments" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.directorySettings" => new[] { "Directory.Read.All" },
            "m365.groups" => new[] { "Group.Read.All", "Directory.Read.All" },
            "usage.onedrive" => new[] { "Reports.Read.All", "Files.Read.All", "Sites.Read.All" },
            "usage.sharepoint" => new[] { "Reports.Read.All", "Sites.Read.All" },
            "usage.teams" => new[] { "Reports.Read.All" },
            "usage.exchange" => new[] { "Reports.Read.All" },
            "org.organization" => new[] { "Organization.Read.All", "Directory.Read.All" },
            "hybrid.aadConnectConfig" => new[] { "OnPremDirectorySynchronization.Read.All", "Organization.Read.All", "Directory.Read.All" },
            "reports.onedrive" => new[] { "Reports.Read.All", "Files.Read.All", "Sites.Read.All" },
            "reports.sharepoint" => new[] { "Reports.Read.All", "Sites.Read.All" },
            "reports.teams" => new[] { "Reports.Read.All" },
            "reports.exchange" => new[] { "Reports.Read.All" },
            "organization.basic" => new[] { "Organization.Read.All", "Directory.Read.All" },
            "licenses.skus" => new[] { "Organization.Read.All", "Directory.Read.All" },
            "domains.list" => new[] { "Domain.Read.All", "Directory.Read.All" },
            _ => Array.Empty<string>()
        };
    }
}

public enum CapabilityStatus
{
    Available,
    Partial,
    Blocked
}

public enum CapabilityPermissionSource
{
    None,
    Delegated,
    Application,
    Both,
    Unknown
}

public sealed record CapabilityMatrix(
    IReadOnlyDictionary<string, CapabilityStatus> Capabilities,
    string[] GrantedScopes,
    AuthMode AuthMode,
    IReadOnlyDictionary<string, CapabilityPermissionSource> CapabilitySources
)
{
    public CapabilityStatus GetStatus(string capabilityKey) =>
        Capabilities.TryGetValue(capabilityKey, out var status) ? status : CapabilityStatus.Blocked;

    public CapabilityPermissionSource GetSource(string capabilityKey) =>
        CapabilitySources.TryGetValue(capabilityKey, out var source) ? source : CapabilityPermissionSource.Unknown;

    public IEnumerable<AccessGap> GetAccessGaps()
    {
        var gaps = new List<AccessGap>();

        foreach (var (key, status) in Capabilities)
        {
            if (status == CapabilityStatus.Blocked)
            {
                gaps.Add(new AccessGap(key, GetRequiredPermissions(key, AuthMode), "Blocked - missing required permissions"));
            }
            else if (status == CapabilityStatus.Partial)
            {
                gaps.Add(new AccessGap(key, GetRequiredPermissions(key, AuthMode), "Partial - limited data available"));
            }
        }

        return gaps;
    }

    public string[] GetRequiredPermissionsForCapability(string capabilityKey)
    {
        return GetRequiredPermissions(capabilityKey, AuthMode);
    }

    public string[] GetMissingPermissionTokens(string capabilityKey)
    {
        var granted = GrantedScopes.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return GetPermissionTokens(capabilityKey)
            .Where(token => !granted.Contains(token))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static string[] GetRequiredPermissions(string capabilityKey, AuthMode authMode)
    {
        var permissionType = authMode == AuthMode.AppOnly ? "Application" : "Delegated";

        return capabilityKey switch
        {
            "entra.users" => new[] { $"{permissionType}: User.Read.All or Directory.Read.All" },
            "entra.groups" => new[] { $"{permissionType}: Group.Read.All or Directory.Read.All" },
            "entra.applications" => new[] { $"{permissionType}: Application.Read.All or Directory.Read.All" },
            "entra.m365groups" => new[] { $"{permissionType}: Group.Read.All or Directory.Read.All" },
            "entra.apps" => new[] { $"{permissionType}: Application.Read.All or Directory.Read.All" },
            "entra.servicePrincipals" => new[] { $"{permissionType}: Application.Read.All or Directory.Read.All" },
            "entra.roles" => new[] { $"{permissionType}: RoleManagement.Read.All or Directory.Read.All" },
            "entra.conditionalAccess" => new[] { $"{permissionType}: Policy.Read.All" },
            "entra.crossTenantAccess" => new[] { $"{permissionType}: Policy.Read.All and Directory.Read.All" },
            "entra.guests" => new[] { $"{permissionType}: User.Read.All and Group.Read.All" },
            "entra.signInSignals" => new[] { $"{permissionType}: AuditLog.Read.All and User.Read.All" },
            "entra.authMethods" => new[] { $"{permissionType}: Reports.Read.All and User.Read.All" },
            "entra.groupInventoryPlus" => new[] { $"{permissionType}: Group.Read.All or Directory.Read.All" },
            "entra.appCredentials" => new[] { $"{permissionType}: Application.Read.All or Directory.Read.All" },
            "entra.appAssignments" => new[] { $"{permissionType}: Application.Read.All and Directory.Read.All" },
            "entra.directorySettings" => new[] { $"{permissionType}: Directory.Read.All" },
            "m365.groups" => new[] { $"{permissionType}: Group.Read.All or Directory.Read.All" },
            "usage.onedrive" => new[] { $"{permissionType}: Reports.Read.All" },
            "usage.sharepoint" => new[] { $"{permissionType}: Reports.Read.All" },
            "usage.teams" => new[] { $"{permissionType}: Reports.Read.All" },
            "usage.exchange" => new[] { $"{permissionType}: Reports.Read.All" },
            "org.organization" => new[] { $"{permissionType}: Organization.Read.All or Directory.Read.All" },
            "hybrid.aadConnectConfig" => new[] { $"{permissionType}: OnPremDirectorySynchronization.Read.All and Organization.Read.All (or Directory.Read.All)" },
            "reports.onedrive" => new[] { $"{permissionType}: Reports.Read.All" },
            "reports.sharepoint" => new[] { $"{permissionType}: Reports.Read.All" },
            "reports.teams" => new[] { $"{permissionType}: Reports.Read.All" },
            "reports.exchange" => new[] { $"{permissionType}: Reports.Read.All" },
            "organization.basic" => new[] { $"{permissionType}: Organization.Read.All or Directory.Read.All" },
            "licenses.skus" => new[] { $"{permissionType}: Organization.Read.All or Directory.Read.All" },
            "domains.list" => new[] { $"{permissionType}: Domain.Read.All or Directory.Read.All" },
            _ => new[] { "Unknown capability" }
        };
    }

    private static string[] GetPermissionTokens(string capabilityKey)
    {
        return capabilityKey switch
        {
            "entra.users" => new[] { "User.Read.All", "Directory.Read.All", "User.ReadBasic.All" },
            "entra.groups" => new[] { "Group.Read.All", "Directory.Read.All" },
            "entra.applications" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.m365groups" => new[] { "Group.Read.All", "Directory.Read.All" },
            "entra.apps" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.servicePrincipals" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.roles" => new[] { "RoleManagement.Read.All", "RoleManagement.Read.Directory", "Directory.Read.All" },
            "entra.conditionalAccess" => new[] { "Policy.Read.All" },
            "entra.crossTenantAccess" => new[] { "Policy.Read.All", "Directory.Read.All" },
            "entra.guests" => new[] { "User.Read.All", "Group.Read.All" },
            "entra.signInSignals" => new[] { "AuditLog.Read.All", "User.Read.All" },
            "entra.authMethods" => new[] { "Reports.Read.All", "User.Read.All" },
            "entra.groupInventoryPlus" => new[] { "Group.Read.All", "Directory.Read.All" },
            "entra.appCredentials" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.appAssignments" => new[] { "Application.Read.All", "Directory.Read.All" },
            "entra.directorySettings" => new[] { "Directory.Read.All" },
            "m365.groups" => new[] { "Group.Read.All", "Directory.Read.All" },
            "usage.onedrive" => new[] { "Reports.Read.All", "Files.Read.All", "Sites.Read.All" },
            "usage.sharepoint" => new[] { "Reports.Read.All", "Sites.Read.All" },
            "usage.teams" => new[] { "Reports.Read.All" },
            "usage.exchange" => new[] { "Reports.Read.All" },
            "org.organization" => new[] { "Organization.Read.All", "Directory.Read.All" },
            "hybrid.aadConnectConfig" => new[] { "OnPremDirectorySynchronization.Read.All", "Organization.Read.All", "Directory.Read.All" },
            "reports.onedrive" => new[] { "Reports.Read.All", "Files.Read.All", "Sites.Read.All" },
            "reports.sharepoint" => new[] { "Reports.Read.All", "Sites.Read.All" },
            "reports.teams" => new[] { "Reports.Read.All" },
            "reports.exchange" => new[] { "Reports.Read.All" },
            "organization.basic" => new[] { "Organization.Read.All", "Directory.Read.All" },
            "licenses.skus" => new[] { "Organization.Read.All", "Directory.Read.All" },
            "domains.list" => new[] { "Domain.Read.All", "Directory.Read.All" },
            _ => Array.Empty<string>()
        };
    }
}

public sealed record AccessGap(string Capability, string[] RequiredScopes, string Reason);
