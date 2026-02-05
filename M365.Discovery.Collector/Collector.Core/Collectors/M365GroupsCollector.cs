using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class M365GroupsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public M365GroupsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var groups = new List<M365GroupRecord>();
        var checkpoint = new CollectorCheckpoint("M365Groups");

        try
        {
            progress?.Report("📥 Fetching M365 Groups...");

            await foreach (var group in _graphClient.PageAllAsync<Microsoft.Graph.Group, IGraphServiceGroupsCollectionPage>(
                client => client.Groups.Request()
                    .Filter("groupTypes/any(c:c eq 'Unified')")
                    .Select("id,displayName,mail,visibility,createdDateTime")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                // All Unified groups (M365 Groups) can potentially be Teams-enabled
                var isTeamsEnabled = true;

                groups.Add(new M365GroupRecord(
                    Id: group.Id,
                    DisplayName: group.DisplayName,
                    Mail: group.Mail,
                    Visibility: group.Visibility,
                    CreatedDateTime: group.CreatedDateTime,
                    IsTeamsEnabled: isTeamsEnabled
                ));

                checkpoint.ItemsProcessed++;

                if (checkpoint.ItemsProcessed % 50 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} M365 groups...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            var teamsCount = groups.Count(g => g.IsTeamsEnabled);
            progress?.Report($"✅ Collected {groups.Count} M365 Groups ({teamsCount} Teams-enabled)");

            return new CollectorResult(
                WorkloadKey: "m365.groups",
                Success: true,
                ItemCount: groups.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {groups.Count} M365 Groups",
                Data: groups,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "m365.groups",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: $"❌ Permission denied - need Group.Read.All or Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;

            return new CollectorResult(
                WorkloadKey: "m365.groups",
                Success: false,
                ItemCount: groups.Count,
                ConfidenceLevel: groups.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {groups.Count} items: {ex.Message}",
                Data: groups.Count > 0 ? groups : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record M365GroupRecord(
    string Id,
    string? DisplayName,
    string? Mail,
    string? Visibility,
    DateTimeOffset? CreatedDateTime,
    bool IsTeamsEnabled
);