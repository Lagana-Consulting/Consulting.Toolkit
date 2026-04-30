// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class EntraApplicationsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public EntraApplicationsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var apps = new List<EntraApplicationRecord>();
        var checkpoint = new CollectorCheckpoint("EntraApplications");

        try
        {
            progress?.Report("📥 Fetching Entra application registrations...");

            await foreach (var app in _graphClient.PageAllAsync<Microsoft.Graph.Application, IGraphServiceApplicationsCollectionPage>(
                client => client.Applications.Request()
                    .Select("id,appId,displayName,createdDateTime")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                apps.Add(new EntraApplicationRecord(
                    Id: app.Id,
                    AppId: app.AppId,
                    DisplayName: app.DisplayName,
                    CreatedDateTime: app.CreatedDateTime
                ));

                checkpoint.ItemsProcessed++;

                if (checkpoint.ItemsProcessed % 100 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} applications...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected {apps.Count} application registrations");

            return new CollectorResult(
                WorkloadKey: "entra.applications",
                Success: true,
                ItemCount: apps.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {apps.Count} Entra applications",
                Data: apps,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "entra.applications",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: $"❌ Permission denied - need Application.Read.All or Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;

            return new CollectorResult(
                WorkloadKey: "entra.applications",
                Success: false,
                ItemCount: apps.Count,
                ConfidenceLevel: apps.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {apps.Count} items: {ex.Message}",
                Data: apps.Count > 0 ? apps : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record EntraApplicationRecord(
    string Id,
    string AppId,
    string? DisplayName,
    DateTimeOffset? CreatedDateTime
);