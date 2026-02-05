using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class ConditionalAccessCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public ConditionalAccessCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var policies = new List<ConditionalAccessPolicyRecord>();
        var checkpoint = new CollectorCheckpoint("ConditionalAccess");

        try
        {
            progress?.Report("?? Fetching Conditional Access Policies...");

            var result = await _graphClient.ExecuteAsync(
                async client => await client.Identity.ConditionalAccess.Policies.Request()
                    .GetAsync(cancellationToken),
                cancellationToken);

            foreach (var policy in result.CurrentPage)
            {
                var includedUsers = policy.Conditions?.Users?.IncludeUsers?.ToList() ?? new List<string>();
                var excludedUsers = policy.Conditions?.Users?.ExcludeUsers?.ToList() ?? new List<string>();
                var includedGroups = policy.Conditions?.Users?.IncludeGroups?.ToList() ?? new List<string>();
                var excludedGroups = policy.Conditions?.Users?.ExcludeGroups?.ToList() ?? new List<string>();

                var includedApps = policy.Conditions?.Applications?.IncludeApplications?.ToList() ?? new List<string>();
                var excludedApps = policy.Conditions?.Applications?.ExcludeApplications?.ToList() ?? new List<string>();

                var grantControls = policy.GrantControls?.BuiltInControls?
                    .Select(c => c.ToString())
                    .ToList() ?? new List<string>();

                var includedLocations = policy.Conditions?.Locations?.IncludeLocations?.ToList() ?? new List<string>();
                var excludedLocations = policy.Conditions?.Locations?.ExcludeLocations?.ToList() ?? new List<string>();

                policies.Add(new ConditionalAccessPolicyRecord(
                    Id: policy.Id,
                    DisplayName: policy.DisplayName,
                    State: policy.State?.ToString() ?? "Unknown",
                    CreatedDateTime: policy.CreatedDateTime,
                    ModifiedDateTime: policy.ModifiedDateTime,
                    
                    IncludedUserCount: includedUsers.Count,
                    ExcludedUserCount: excludedUsers.Count,
                    IncludedGroupCount: includedGroups.Count,
                    ExcludedGroupCount: excludedGroups.Count,
                    IncludeAllUsers: includedUsers.Contains("All"),
                    
                    IncludedAppCount: includedApps.Count,
                    ExcludedAppCount: excludedApps.Count,
                    IncludeAllApps: includedApps.Contains("All"),
                    
                    GrantControls: string.Join(", ", grantControls),
                    RequireMultiFactor: grantControls.Contains("mfa"),
                    RequireCompliantDevice: grantControls.Contains("compliantDevice"),
                    RequireHybridJoin: grantControls.Contains("domainJoinedDevice"),
                    
                    IncludedLocationCount: includedLocations.Count,
                    ExcludedLocationCount: excludedLocations.Count,
                    HasNamedLocations: includedLocations.Count > 0 || excludedLocations.Count > 0,
                    
                    HasPlatformConditions: policy.Conditions?.Platforms != null,
                    HasDeviceStateConditions: policy.Conditions?.Devices != null,
                    
                    SessionControls: policy.SessionControls != null ? "Configured" : "None"
                ));

                checkpoint.ItemsProcessed++;
                if (checkpoint.ItemsProcessed % 5 == 0)
                {
                    progress?.Report($"  ? Processed {checkpoint.ItemsProcessed} policies...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            var enabledCount = policies.Count(p => p.State == "enabled");
            
            progress?.Report($"? Collected {policies.Count} Conditional Access policies ({enabledCount} enabled)");

            return new CollectorResult(
                WorkloadKey: "entra.conditionalAccess",
                Success: true,
                ItemCount: policies.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {policies.Count} CA policies",
                Data: policies,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.conditionalAccess",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "? Permission denied - need Policy.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.conditionalAccess",
                Success: false,
                ItemCount: policies.Count,
                ConfidenceLevel: policies.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"? Partial failure after {policies.Count} items: {ex.Message}",
                Data: policies.Count > 0 ? policies : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record ConditionalAccessPolicyRecord(
    string Id,
    string DisplayName,
    string State,
    DateTimeOffset? CreatedDateTime,
    DateTimeOffset? ModifiedDateTime,
    
    int IncludedUserCount,
    int ExcludedUserCount,
    int IncludedGroupCount,
    int ExcludedGroupCount,
    bool IncludeAllUsers,
    
    int IncludedAppCount,
    int ExcludedAppCount,
    bool IncludeAllApps,
    
    string GrantControls,
    bool RequireMultiFactor,
    bool RequireCompliantDevice,
    bool RequireHybridJoin,
    
    int IncludedLocationCount,
    int ExcludedLocationCount,
    bool HasNamedLocations,
    
    bool HasPlatformConditions,
    bool HasDeviceStateConditions,
    
    string SessionControls
);