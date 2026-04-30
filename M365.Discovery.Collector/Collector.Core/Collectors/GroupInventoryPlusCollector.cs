// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class GroupInventoryPlusCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public GroupInventoryPlusCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var groups = new List<GroupInventoryRecord>();
        var checkpoint = new CollectorCheckpoint("GroupInventoryPlus");

        try
        {
            progress?.Report("📥 Fetching group inventory (owners & member counts)...");

            await foreach (var group in _graphClient.PageAllAsync<Microsoft.Graph.Group, IGraphServiceGroupsCollectionPage>(
                client => client.Groups.Request()
                    .Select("id,displayName,mailEnabled,securityEnabled,groupTypes,visibility,membershipRule,createdDateTime,mail")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                int ownerCount = 0;
                try
                {
                    var owners = await _graphClient.ExecuteAsync(
                        async client => await client.Groups[group.Id].Owners.Request()
                            .Select("id")
                            .GetAsync(cancellationToken),
                        cancellationToken);
                    ownerCount = owners?.Count ?? 0;
                }
                catch
                {
                    // Unable to read owners - continue
                }

                int memberCount = 0;
                try
                {
                    var members = await _graphClient.ExecuteAsync(
                        async client => await client.Groups[group.Id].Members.Request()
                            .Select("id")
                            .GetAsync(cancellationToken),
                        cancellationToken);
                    memberCount = members?.Count ?? 0;
                }
                catch
                {
                    // Unable to read members - continue
                }

                var isM365Group = group.GroupTypes?.Contains("Unified") ?? false;
                var isDynamic = !string.IsNullOrEmpty(group.MembershipRule);

                groups.Add(new GroupInventoryRecord(
                    Id: group.Id,
                    DisplayName: group.DisplayName,
                    Mail: group.Mail,
                    CreatedDateTime: group.CreatedDateTime,
                    
                    SecurityEnabled: group.SecurityEnabled ?? false,
                    MailEnabled: group.MailEnabled ?? false,
                    IsM365Group: isM365Group,
                    Visibility: group.Visibility,
                    
                    MemberCount: memberCount,
                    OwnerCount: ownerCount,
                    
                    IsDynamic: isDynamic,
                    MembershipRule: group.MembershipRule,
                    
                    IsOrphaned: ownerCount == 0,
                    IsLargeGroup: memberCount > 1000,
                    IsEmptyGroup: memberCount == 0 && ownerCount <= 1
                ));

                checkpoint.ItemsProcessed++;
                if (checkpoint.ItemsProcessed % 100 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} groups...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            
            var orphanedCount = groups.Count(g => g.IsOrphaned);
            var largeGroupCount = groups.Count(g => g.IsLargeGroup);
            
            progress?.Report($"✅ Collected {groups.Count} groups ({orphanedCount} orphaned, {largeGroupCount} large)");

            return new CollectorResult(
                WorkloadKey: "entra.groupInventoryPlus",
                Success: true,
                ItemCount: groups.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {groups.Count} groups",
                Data: groups,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.groupInventoryPlus",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Group.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.groupInventoryPlus",
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

public sealed record GroupInventoryRecord(
    string Id,
    string? DisplayName,
    string? Mail,
    DateTimeOffset? CreatedDateTime,
    
    bool SecurityEnabled,
    bool MailEnabled,
    bool IsM365Group,
    string? Visibility,
    
    int MemberCount,
    int OwnerCount,
    
    bool IsDynamic,
    string? MembershipRule,
    
    bool IsOrphaned,
    bool IsLargeGroup,
    bool IsEmptyGroup
);