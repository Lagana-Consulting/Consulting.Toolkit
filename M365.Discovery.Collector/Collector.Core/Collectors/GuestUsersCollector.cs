// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class GuestUsersCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public GuestUsersCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var guests = new List<GuestUserRecord>();
        var checkpoint = new CollectorCheckpoint("GuestUsers");

        try
        {
            progress?.Report("📥 Fetching guest users...");

            await foreach (var user in _graphClient.PageAllAsync<Microsoft.Graph.User, IGraphServiceUsersCollectionPage>(
                client => client.Users.Request()
                    .Filter("userType eq 'Guest'")
                    .Select("id,displayName,userPrincipalName,userType,externalUserState,externalUserStateChangeDateTime,createdDateTime,mail,accountEnabled")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                int groupMembershipCount = 0;
                try
                {
                    var memberOf = await _graphClient.ExecuteAsync(
                        async client => await client.Users[user.Id].MemberOf.Request()
                            .Select("id")
                            .GetAsync(cancellationToken),
                        cancellationToken);
                    groupMembershipCount = memberOf?.Count ?? 0;
                }
                catch
                {
                    // Unable to read memberships - continue
                }

                var daysSinceCreated = user.CreatedDateTime.HasValue 
                    ? (int)(DateTimeOffset.UtcNow - user.CreatedDateTime.Value).TotalDays 
                    : 0;

                guests.Add(new GuestUserRecord(
                    Id: user.Id,
                    DisplayName: user.DisplayName,
                    UserPrincipalName: user.UserPrincipalName,
                    Mail: user.Mail,
                    ExternalUserState: user.ExternalUserState,
                    ExternalUserStateChangeDateTime: user.ExternalUserStateChangeDateTime,
                    CreatedDateTime: user.CreatedDateTime,
                    AccountEnabled: user.AccountEnabled ?? false,
                    GroupMembershipCount: groupMembershipCount,
                    
                    IsOrphaned: groupMembershipCount == 0,
                    IsPendingAcceptance: user.ExternalUserState == "PendingAcceptance",
                    DaysSinceCreated: daysSinceCreated
                ));

                checkpoint.ItemsProcessed++;
                if (checkpoint.ItemsProcessed % 50 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} guests...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            
            var orphanedCount = guests.Count(g => g.IsOrphaned);
            var pendingCount = guests.Count(g => g.IsPendingAcceptance);
            
            progress?.Report($"✅ Collected {guests.Count} guest users ({orphanedCount} orphaned, {pendingCount} pending)");

            return new CollectorResult(
                WorkloadKey: "entra.guests",
                Success: true,
                ItemCount: guests.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {guests.Count} guest users",
                Data: guests,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.guests",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need User.Read.All + Group.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.guests",
                Success: false,
                ItemCount: guests.Count,
                ConfidenceLevel: guests.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {guests.Count} items: {ex.Message}",
                Data: guests.Count > 0 ? guests : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record GuestUserRecord(
    string Id,
    string? DisplayName,
    string? UserPrincipalName,
    string? Mail,
    string? ExternalUserState,
    DateTimeOffset? ExternalUserStateChangeDateTime,
    DateTimeOffset? CreatedDateTime,
    bool AccountEnabled,
    int GroupMembershipCount,
    
    bool IsOrphaned,
    bool IsPendingAcceptance,
    int DaysSinceCreated
);