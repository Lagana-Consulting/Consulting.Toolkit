using Microsoft.Graph;

namespace Collector.App.Services;

public class AppRegistrationService
{
    private readonly GraphServiceClient _graphClient;

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
                // Start with minimal Microsoft Graph permissions
                new RequiredResourceAccess
                {
                    ResourceAppId = "00000003-0000-0000-c000-000000000000", // Microsoft Graph
                    ResourceAccess = new List<ResourceAccess>
                    {
                        new ResourceAccess
                        {
                            Id = Guid.Parse("e1fe6dd8-ba31-4d61-89e7-88639da4683d"), // User.Read
                            Type = "Scope"
                        }
                    }
                }
            }
        };

        var createdApp = await _graphClient.Applications.Request().AddAsync(application);
        
        return (createdApp.AppId, createdApp.Id);
    }

    public async Task<PermissionAddResult> AddPermissionsAsync(string appObjectId, string[] requiredPermissions)
    {
        // Microsoft Graph Resource App ID
        const string graphResourceId = "00000003-0000-0000-c000-000000000000";

        // DELEGATED Permission GUIDs (all verified)
        var permissionMap = new Dictionary<string, Guid>
        {
            { "User.Read.All", Guid.Parse("a154be20-db9c-4678-8ab7-66f6cc099a59") },
            { "Group.Read.All", Guid.Parse("5f8c59db-677d-491f-a6b8-5f174b11ec1d") },
            { "Directory.Read.All", Guid.Parse("06da0dbc-49e2-44d2-8312-53f166ab848a") },
            { "Application.Read.All", Guid.Parse("c79f8feb-a9db-4090-85f9-90d820caa0eb") },
            { "Reports.Read.All", Guid.Parse("02e97553-ed7b-43d0-ab3c-f8bace0d040c") },
            { "Organization.Read.All", Guid.Parse("4908d5b9-3fb2-4b1e-9336-1888b7937185") },
            { "Domain.Read.All", Guid.Parse("2f9ee017-59c1-4f1d-9472-bd5529a7b311") }
        };

        var requestedAccess = requiredPermissions
            .Where(p => permissionMap.ContainsKey(p))
            .Select(p => new ResourceAccess
            {
                Id = permissionMap[p],
                Type = "Scope"
            })
            .ToList();

        var application = await _graphClient.Applications[appObjectId].Request().GetAsync();
        
        var requiredResourceAccess = application.RequiredResourceAccess?.ToList() ?? new List<RequiredResourceAccess>();
        
        var graphResource = requiredResourceAccess
            .FirstOrDefault(r => r.ResourceAppId == graphResourceId);

        List<string> existingPermissions = new();
        List<string> newPermissions = new();
        
        if (graphResource == null)
        {
            // First time - no permissions exist yet
            graphResource = new RequiredResourceAccess
            {
                ResourceAppId = graphResourceId,
                ResourceAccess = requestedAccess
            };
            requiredResourceAccess.Add(graphResource);
            
            // All permissions are new
            newPermissions = requiredPermissions.Where(p => permissionMap.ContainsKey(p)).ToList();
        }
        else
        {
            // Permissions already exist - merge
            var existingAccess = graphResource.ResourceAccess?.ToList() ?? new List<ResourceAccess>();
            var existingIds = existingAccess
                .Where(ea => ea.Id.HasValue)
                .Select(r => r.Id.Value)
                .ToHashSet();
            
            // Track what we already have
            var reverseMap = permissionMap.ToDictionary(kvp => kvp.Value, kvp => kvp.Key);
            existingPermissions = existingAccess
                .Where(ea => ea.Id.HasValue && reverseMap.ContainsKey(ea.Id.Value))
                .Select(ea => reverseMap[ea.Id!.Value])
                .ToList();
            
            // Add only new permissions
            foreach (var newAccess in requestedAccess.Where(r => r.Id.HasValue && !existingIds.Contains(r.Id.Value)))
            {
                existingAccess.Add(newAccess);
                if (newAccess.Id.HasValue && reverseMap.TryGetValue(newAccess.Id.Value, out var permName))
                {
                    newPermissions.Add(permName);
                }
            }
            
            // Update the resource with merged permissions
            graphResource.ResourceAccess = existingAccess;
        }

        // Update the application with all resources
        application.RequiredResourceAccess = requiredResourceAccess;
        await _graphClient.Applications[appObjectId].Request().UpdateAsync(application);
        
        return new PermissionAddResult(
            Requested: requiredPermissions,
            AlreadyExisted: existingPermissions.ToArray(),
            NewlyAdded: newPermissions.ToArray()
        );
    }
    
    public record PermissionAddResult(
        string[] Requested,
        string[] AlreadyExisted,
        string[] NewlyAdded
    );

    public string GetAdminConsentUrl(string clientId, string tenantId)
    {
        var redirectUri = Uri.EscapeDataString("http://localhost");
        return $"https://login.microsoftonline.com/{tenantId}/adminconsent?" +
               $"client_id={clientId}&" +
               $"redirect_uri={redirectUri}";
    }
}