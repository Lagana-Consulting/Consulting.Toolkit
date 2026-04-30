// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class EntraGroupsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public EntraGroupsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var groups = new List<EntraGroupRecord>();
        var checkpoint = new CollectorCheckpoint("EntraGroups");

        try
        {
            progress?.Report("📥 Fetching Entra groups...");

            await foreach (var group in _graphClient.PageAllAsync<Microsoft.Graph.Group, IGraphServiceGroupsCollectionPage>(
                client => client.Groups.Request()
                    .Select("id,displayName,mail,mailEnabled,securityEnabled,groupTypes,createdDateTime")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                groups.Add(new EntraGroupRecord(
                    Id: group.Id,
                    DisplayName: group.DisplayName,
                    Mail: group.Mail,
                    MailEnabled: group.MailEnabled ?? false,
                    SecurityEnabled: group.SecurityEnabled ?? false,
                    IsM365Group: group.GroupTypes?.Contains("Unified") ?? false,
                    CreatedDateTime: group.CreatedDateTime
                ));

                checkpoint.ItemsProcessed++;

                if (checkpoint.ItemsProcessed % 100 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} groups...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected {groups.Count} groups");

            return new CollectorResult(
                WorkloadKey: "entra.groups",
                Success: true,
                ItemCount: groups.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {groups.Count} Entra groups",
                Data: groups,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "entra.groups",
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
                WorkloadKey: "entra.groups",
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

public sealed record EntraGroupRecord(
    string Id,
    string? DisplayName,
    string? Mail,
    bool MailEnabled,
    bool SecurityEnabled,
    bool IsM365Group,
    DateTimeOffset? CreatedDateTime
);