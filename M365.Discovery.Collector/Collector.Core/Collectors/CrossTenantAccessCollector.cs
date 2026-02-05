using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class CrossTenantAccessCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public CrossTenantAccessCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var settings = new List<CrossTenantAccessRecord>();
        var checkpoint = new CollectorCheckpoint("CrossTenantAccess");

        try
        {
            progress?.Report("📥 Fetching cross-tenant access settings...");

            // Get default cross-tenant access settings
            var defaultSettings = await _graphClient.ExecuteAsync(
                async client => await client.Policies.CrossTenantAccessPolicy.Default.Request()
                    .GetAsync(cancellationToken),
                cancellationToken);

            if (defaultSettings != null)
            {
                settings.Add(new CrossTenantAccessRecord(
                    TenantId: "default",
                    DisplayName: "Default Settings",
                    IsDefaultPolicy: true,
                    InboundAllowed: true,
                    OutboundAllowed: true,
                    B2BDirectConnectInboundAllowed: false,
                    B2BDirectConnectOutboundAllowed: false,
                    HasRestrictions: false
                ));
            }

            // Get partner-specific configurations
            var partners = await _graphClient.ExecuteAsync(
                async client => await client.Policies.CrossTenantAccessPolicy.Partners.Request()
                    .GetAsync(cancellationToken),
                cancellationToken);

            foreach (var partner in partners.CurrentPage)
            {
                settings.Add(new CrossTenantAccessRecord(
                    TenantId: partner.TenantId,
                    DisplayName: partner.TenantId,
                    IsDefaultPolicy: false,
                    InboundAllowed: true,
                    OutboundAllowed: true,
                    B2BDirectConnectInboundAllowed: false,
                    B2BDirectConnectOutboundAllowed: false,
                    HasRestrictions: true
                ));

                checkpoint.ItemsProcessed++;
            }

            checkpoint.Status = CheckpointStatus.Completed;
            
            progress?.Report($"✅ Collected {settings.Count} cross-tenant access configurations");

            return new CollectorResult(
                WorkloadKey: "entra.crossTenantAccess",
                Success: true,
                ItemCount: settings.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {settings.Count} cross-tenant settings",
                Data: settings,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.crossTenantAccess",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Policy.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.crossTenantAccess",
                Success: false,
                ItemCount: settings.Count,
                ConfidenceLevel: settings.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {settings.Count} items: {ex.Message}",
                Data: settings.Count > 0 ? settings : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record CrossTenantAccessRecord(
    string TenantId,
    string DisplayName,
    bool IsDefaultPolicy,
    bool InboundAllowed,
    bool OutboundAllowed,
    bool B2BDirectConnectInboundAllowed,
    bool B2BDirectConnectOutboundAllowed,
    bool HasRestrictions
);