using Microsoft.Graph;
using System.IdentityModel.Tokens.Jwt;

namespace Collector.Graph;

public sealed class PermissionDetector
{
    private readonly TokenInfo _tokenInfo;

    public PermissionDetector(TokenInfo tokenInfo)
    {
        _tokenInfo = tokenInfo ?? throw new ArgumentNullException(nameof(tokenInfo));
    }

    /// <summary>
    /// Build capability matrix from granted scopes/roles
    /// </summary>
    public CapabilityMatrix DetectCapabilities()
    {
        var permissions = _tokenInfo.GrantedScopes.ToHashSet(StringComparer.OrdinalIgnoreCase);
        
        var capabilities = new Dictionary<string, CapabilityStatus>
        {
            ["entra.users"] = DetectEntraUsers(permissions),
            ["entra.groups"] = DetectEntraGroups(permissions),
            ["entra.m365groups"] = DetectEntraGroups(permissions), // Same as groups
            ["entra.apps"] = DetectEntraApps(permissions),
            ["entra.servicePrincipals"] = DetectEntraServicePrincipals(permissions),
            ["entra.roles"] = DetectEntraRoles(permissions),
            ["reports.onedrive"] = DetectReportsOneDrive(permissions),
            ["reports.sharepoint"] = DetectReportsSharePoint(permissions),
            ["reports.teams"] = DetectReportsTeams(permissions),
            ["reports.exchange"] = DetectReportsExchange(permissions),
            ["organization.basic"] = DetectOrganization(permissions),
            ["licenses.skus"] = DetectLicenses(permissions),
            ["domains.list"] = DetectDomains(permissions),
        };

        return new CapabilityMatrix(capabilities, _tokenInfo.GrantedScopes, _tokenInfo.AuthMode);
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
}

public enum CapabilityStatus
{
    Available,
    Partial,
    Blocked
}

public sealed record CapabilityMatrix(
    IReadOnlyDictionary<string, CapabilityStatus> Capabilities,
    string[] GrantedScopes,
    AuthMode AuthMode  // No longer Collector.Core.AuthMode
)
{
    public CapabilityStatus GetStatus(string capabilityKey) =>
        Capabilities.TryGetValue(capabilityKey, out var status) ? status : CapabilityStatus.Blocked;

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

    private static string[] GetRequiredPermissions(string capabilityKey, AuthMode authMode)
    {
        var permissionType = authMode == AuthMode.AppOnly ? "Application" : "Delegated";
        
        return capabilityKey switch
        {
            "entra.users" => new[] { $"{permissionType}: User.Read.All or Directory.Read.All" },
            "entra.groups" => new[] { $"{permissionType}: Group.Read.All or Directory.Read.All" },
            "entra.m365groups" => new[] { $"{permissionType}: Group.Read.All or Directory.Read.All" },
            "entra.apps" => new[] { $"{permissionType}: Application.Read.All or Directory.Read.All" },
            "entra.servicePrincipals" => new[] { $"{permissionType}: Application.Read.All or Directory.Read.All" },
            "entra.roles" => new[] { $"{permissionType}: RoleManagement.Read.All or Directory.Read.All" },
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
}

public sealed record AccessGap(string Capability, string[] RequiredScopes, string Reason);