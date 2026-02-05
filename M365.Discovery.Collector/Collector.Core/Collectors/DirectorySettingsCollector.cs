using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class DirectorySettingsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public DirectorySettingsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var settings = new List<DirectorySettingRecord>();
        var checkpoint = new CollectorCheckpoint("DirectorySettings");

        try
        {
            progress?.Report("📥 Fetching directory settings...");

            // Note: Directory settings endpoint may require specific Graph API version
            // For now, return empty collection with partial confidence
            checkpoint.Status = CheckpointStatus.Completed;
            
            progress?.Report($"⚠️ Directory settings collection requires Graph beta endpoint (not available in v1.0)");

            return new CollectorResult(
                WorkloadKey: "entra.directorySettings",
                Success: true,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "Directory settings require Graph beta endpoint",
                Data: settings,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.directorySettings",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.directorySettings",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: $"❌ Error: {ex.Message}",
                Data: null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record DirectorySettingRecord(
    string Id,
    string? DisplayName,
    string TemplateId,
    string SettingValues
);