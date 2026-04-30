// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class EntraUsersCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public EntraUsersCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var users = new List<EntraUserRecord>();
        var checkpoint = new CollectorCheckpoint("EntraUsers");

        try
        {
            progress?.Report("📥 Fetching Entra users...");

            await foreach (var user in _graphClient.PageAllAsync<Microsoft.Graph.User, IGraphServiceUsersCollectionPage>(
                client => client.Users.Request()
                    .Select("id,displayName,userPrincipalName,mail,accountEnabled,createdDateTime,userType,assignedLicenses")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                users.Add(new EntraUserRecord(
                    Id: user.Id,
                    DisplayName: user.DisplayName,
                    UserPrincipalName: user.UserPrincipalName,
                    Mail: user.Mail,
                    AccountEnabled: user.AccountEnabled ?? false,
                    CreatedDateTime: user.CreatedDateTime,
                    UserType: user.UserType,
                    LicenseCount: user.AssignedLicenses?.Count() ?? 0
                ));

                checkpoint.ItemsProcessed++;

                if (checkpoint.ItemsProcessed % 100 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} users...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected {users.Count} users");

            return new CollectorResult(
                WorkloadKey: "entra.users",
                Success: true,
                ItemCount: users.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {users.Count} Entra users",
                Data: users,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "entra.users",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: $"❌ Permission denied - need User.Read.All or Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;

            return new CollectorResult(
                WorkloadKey: "entra.users",
                Success: false,
                ItemCount: users.Count,
                ConfidenceLevel: users.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {users.Count} items: {ex.Message}",
                Data: users.Count > 0 ? users : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record EntraUserRecord(
    string Id,
    string? DisplayName,
    string? UserPrincipalName,
    string? Mail,
    bool AccountEnabled,
    DateTimeOffset? CreatedDateTime,
    string? UserType,
    int LicenseCount
);