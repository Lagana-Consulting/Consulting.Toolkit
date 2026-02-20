using Microsoft.Graph;

namespace Collector.App.Services;

public class AppRegistrationService
{
    private readonly GraphServiceClient _graphClient;
    private const string GraphResourceAppId = "00000003-0000-0000-c000-000000000000";

    public AppRegistrationService(GraphServiceClient graphClient)
    {
        _graphClient = graphClient;
    }

    public async Task<(string ClientId, string AppObjectId)> CreateAppRegistrationAsync(string displayName)
    {
        var application = new Microsoft.Graph.Application
        {
            DisplayName = displayName,
            SignInAudience = "AzureADMultipleOrgs",
            PublicClient = new PublicClientApplication
            {
                RedirectUris = new List<string> { "http://localhost" }
            },
            RequiredResourceAccess = new List<RequiredResourceAccess>
            {
                new RequiredResourceAccess
                {
                    ResourceAppId = GraphResourceAppId,
                    ResourceAccess = new List<ResourceAccess>
                    {
                        new ResourceAccess
                        {
                            Id = Guid.Parse("e1fe6dd8-ba31-4d61-89e7-88639da4683d"), // User.Read (delegated)
                            Type = "Scope"
                        }
                    }
                }
            }
        };

        var createdApp = await _graphClient.Applications.Request().AddAsync(application);
        return (createdApp.AppId, createdApp.Id);
    }

    public async Task<PermissionAddResult> AddPermissionsAsync(
        string appObjectId,
        string[] requiredPermissions,
        bool includeDelegated = true,
        bool includeApplication = true)
    {
        var graphSp = await GetGraphServicePrincipalAsync();

        var requestedAccess = ResolveGraphResourceAccess(
            graphSp,
            requiredPermissions,
            includeDelegated,
            includeApplication,
            out var unresolved);

        if (requestedAccess.Count == 0)
        {
            return new PermissionAddResult(
                Requested: requiredPermissions,
                AlreadyExisted: Array.Empty<string>(),
                NewlyAdded: Array.Empty<string>(),
                Unresolved: unresolved.ToArray(),
                AddedDelegatedCount: 0,
                AddedApplicationCount: 0,
                ExistingDelegatedCount: 0,
                ExistingApplicationCount: 0);
        }

        var application = await _graphClient.Applications[appObjectId].Request().GetAsync();
        var requiredResourceAccess = application.RequiredResourceAccess?.ToList() ?? new List<RequiredResourceAccess>();

        var graphResource = requiredResourceAccess.FirstOrDefault(r => r.ResourceAppId == GraphResourceAppId);
        var existingPermissions = new List<string>();
        var newPermissions = new List<string>();

        if (graphResource == null)
        {
            graphResource = new RequiredResourceAccess
            {
                ResourceAppId = GraphResourceAppId,
                ResourceAccess = requestedAccess.Select(x => x.ResourceAccess).ToList()
            };
            requiredResourceAccess.Add(graphResource);
            newPermissions.AddRange(requestedAccess.Select(x => x.DisplayName));
        }
        else
        {
            var existingAccess = graphResource.ResourceAccess?.ToList() ?? new List<ResourceAccess>();
            var existingKeys = existingAccess
                .Where(e => e.Id.HasValue)
                .Select(e => $"{e.Type}:{e.Id!.Value}")
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            var reverseLookup = requestedAccess.ToDictionary(
                k => $"{k.ResourceAccess.Type}:{k.ResourceAccess.Id}",
                v => v.DisplayName,
                StringComparer.OrdinalIgnoreCase);

            foreach (var ea in existingAccess.Where(e => e.Id.HasValue))
            {
                var key = $"{ea.Type}:{ea.Id!.Value}";
                if (reverseLookup.TryGetValue(key, out var name))
                {
                    existingPermissions.Add(name);
                }
            }

            foreach (var request in requestedAccess)
            {
                var key = $"{request.ResourceAccess.Type}:{request.ResourceAccess.Id}";
                if (existingKeys.Contains(key))
                {
                    continue;
                }

                existingAccess.Add(request.ResourceAccess);
                newPermissions.Add(request.DisplayName);
            }

            graphResource.ResourceAccess = existingAccess;
        }

        application.RequiredResourceAccess = requiredResourceAccess;
        await _graphClient.Applications[appObjectId].Request().UpdateAsync(application);

        var addedDelegated = newPermissions.Count(p => p.StartsWith("Delegated:", StringComparison.OrdinalIgnoreCase));
        var addedApplication = newPermissions.Count(p => p.StartsWith("Application:", StringComparison.OrdinalIgnoreCase));
        var existingDelegated = existingPermissions.Count(p => p.StartsWith("Delegated:", StringComparison.OrdinalIgnoreCase));
        var existingApplication = existingPermissions.Count(p => p.StartsWith("Application:", StringComparison.OrdinalIgnoreCase));

        return new PermissionAddResult(
            Requested: requiredPermissions,
            AlreadyExisted: existingPermissions.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x).ToArray(),
            NewlyAdded: newPermissions.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x).ToArray(),
            Unresolved: unresolved.Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x).ToArray(),
            AddedDelegatedCount: addedDelegated,
            AddedApplicationCount: addedApplication,
            ExistingDelegatedCount: existingDelegated,
            ExistingApplicationCount: existingApplication);
    }

    public record PermissionAddResult(
        string[] Requested,
        string[] AlreadyExisted,
        string[] NewlyAdded,
        string[] Unresolved,
        int AddedDelegatedCount,
        int AddedApplicationCount,
        int ExistingDelegatedCount,
        int ExistingApplicationCount
    );

    public record ConsentProfile(string Name, string[] Permissions, string AdminConsentUrl);

    public IReadOnlyList<ConsentProfile> GetConsentProfiles(string clientId, string tenantId)
    {
        var url = GetAdminConsentUrl(clientId, tenantId);
        var profiles = new List<ConsentProfile>
        {
            new("Core-Entra-Phase3", new[]
            {
                "RoleManagement.Read.Directory",
                "Policy.Read.All",
                "User.Read.All",
                "Group.Read.All",
                "Application.Read.All",
                "Directory.Read.All"
            }, url),
            new("Core-M365-Reports", new[]
            {
                "Reports.Read.All",
                "Organization.Read.All",
                "Domain.Read.All"
            }, url),
            new("Hybrid-Connect", new[]
            {
                "OnPremDirectorySynchronization.Read.All"
            }, url)
        };

        return profiles;
    }

    public string GetAdminConsentUrl(string clientId, string tenantId)
    {
        var redirectUri = Uri.EscapeDataString("http://localhost");
        return $"https://login.microsoftonline.com/{tenantId}/adminconsent?" +
               $"client_id={clientId}&" +
               $"redirect_uri={redirectUri}";
    }

    private async Task<ServicePrincipal> GetGraphServicePrincipalAsync()
    {
        var graphSps = await _graphClient.ServicePrincipals
            .Request()
            .Filter($"appId eq '{GraphResourceAppId}'")
            .Select("id,appId,displayName,appRoles,oauth2PermissionScopes")
            .GetAsync();

        var graphSp = graphSps?.CurrentPage?.FirstOrDefault();
        if (graphSp == null)
        {
            throw new InvalidOperationException("Microsoft Graph service principal was not found in the tenant.");
        }

        return graphSp;
    }

    private static List<ResolvedPermission> ResolveGraphResourceAccess(
        ServicePrincipal graphSp,
        IEnumerable<string> permissions,
        bool includeDelegated,
        bool includeApplication,
        out List<string> unresolved)
    {
        unresolved = new List<string>();
        var resolved = new List<ResolvedPermission>();

        foreach (var permission in permissions.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var resolvedAny = false;

            if (includeDelegated)
            {
                var scope = graphSp.Oauth2PermissionScopes?
                    .FirstOrDefault(s => s.IsEnabled == true &&
                                         string.Equals(s.Value, permission, StringComparison.OrdinalIgnoreCase));

                if (scope?.Id != null)
                {
                    resolved.Add(new ResolvedPermission(
                        new ResourceAccess { Id = scope.Id, Type = "Scope" },
                        $"Delegated:{permission}"));
                    resolvedAny = true;
                }
            }

            if (includeApplication)
            {
                var role = graphSp.AppRoles?
                    .FirstOrDefault(r => r.IsEnabled == true &&
                                         r.AllowedMemberTypes != null &&
                                         r.AllowedMemberTypes.Contains("Application") &&
                                         string.Equals(r.Value, permission, StringComparison.OrdinalIgnoreCase));

                if (role?.Id != null)
                {
                    resolved.Add(new ResolvedPermission(
                        new ResourceAccess { Id = role.Id, Type = "Role" },
                        $"Application:{permission}"));
                    resolvedAny = true;
                }
            }

            if (!resolvedAny)
            {
                unresolved.Add(permission);
            }
        }

        return resolved;
    }

    private sealed record ResolvedPermission(ResourceAccess ResourceAccess, string DisplayName);
}
