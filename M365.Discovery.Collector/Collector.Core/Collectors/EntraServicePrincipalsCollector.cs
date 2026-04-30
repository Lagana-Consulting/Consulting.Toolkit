// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class EntraServicePrincipalsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public EntraServicePrincipalsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var sps = new List<EntraServicePrincipalRecord>();
        var checkpoint = new CollectorCheckpoint("EntraServicePrincipals");

        try
        {
            progress?.Report("📥 Fetching Entra service principals...");

            await foreach (var sp in _graphClient.PageAllAsync<Microsoft.Graph.ServicePrincipal, IGraphServiceServicePrincipalsCollectionPage>(
                client => client.ServicePrincipals.Request()
                    .Select("id,appId,displayName,servicePrincipalType")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                sps.Add(new EntraServicePrincipalRecord(
                    Id: sp.Id,
                    AppId: sp.AppId,
                    DisplayName: sp.DisplayName,
                    ServicePrincipalType: sp.ServicePrincipalType
                ));

                checkpoint.ItemsProcessed++;

                if (checkpoint.ItemsProcessed % 100 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} service principals...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected {sps.Count} service principals");

            return new CollectorResult(
                WorkloadKey: "entra.servicePrincipals",
                Success: true,
                ItemCount: sps.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {sps.Count} Entra service principals",
                Data: sps,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "entra.servicePrincipals",
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
                WorkloadKey: "entra.servicePrincipals",
                Success: false,
                ItemCount: sps.Count,
                ConfidenceLevel: sps.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {sps.Count} items: {ex.Message}",
                Data: sps.Count > 0 ? sps : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record EntraServicePrincipalRecord(
    string Id,
    string AppId,
    string? DisplayName,
    string? ServicePrincipalType
);