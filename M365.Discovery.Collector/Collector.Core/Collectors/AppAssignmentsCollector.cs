using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class AppAssignmentsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public AppAssignmentsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var assignments = new List<AppAssignmentRecord>();
        var checkpoint = new CollectorCheckpoint("AppAssignments");

        try
        {
            progress?.Report("📥 Fetching service principal app role assignments...");

            await foreach (var sp in _graphClient.PageAllAsync<Microsoft.Graph.ServicePrincipal, IGraphServiceServicePrincipalsCollectionPage>(
                client => client.ServicePrincipals.Request()
                    .Select("id,appId,displayName,servicePrincipalType")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                try
                {
                    var spAssignments = await _graphClient.ExecuteAsync(
                        async client => await client.ServicePrincipals[sp.Id].AppRoleAssignments.Request()
                            .GetAsync(cancellationToken),
                        cancellationToken);

                    foreach (var assignment in spAssignments.CurrentPage)
                    {
                        assignments.Add(new AppAssignmentRecord(
                            PrincipalId: assignment.PrincipalId?.ToString(),
                            PrincipalDisplayName: sp.DisplayName,
                            PrincipalType: assignment.PrincipalType,
                            ResourceId: assignment.ResourceId?.ToString(),
                            ResourceDisplayName: assignment.ResourceDisplayName ?? "Unknown",
                            AppRoleId: assignment.AppRoleId?.ToString(),
                            CreatedDateTime: assignment.CreatedDateTime,
                            
                            IsGraphAssignment: assignment.ResourceDisplayName?.Contains("Microsoft Graph") ?? false
                        ));
                    }
                }
                catch
                {
                    // Unable to read assignments for this SP - continue
                }

                checkpoint.ItemsProcessed++;
                if (checkpoint.ItemsProcessed % 50 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} service principals...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            
            var graphAssignments = assignments.Count(a => a.IsGraphAssignment);
            
            progress?.Report($"✅ Collected {assignments.Count} app role assignments ({graphAssignments} to MS Graph)");

            return new CollectorResult(
                WorkloadKey: "entra.appAssignments",
                Success: true,
                ItemCount: assignments.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {assignments.Count} app assignments",
                Data: assignments,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.appAssignments",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Application.Read.All + Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.appAssignments",
                Success: false,
                ItemCount: assignments.Count,
                ConfidenceLevel: assignments.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {assignments.Count} items: {ex.Message}",
                Data: assignments.Count > 0 ? assignments : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record AppAssignmentRecord(
    string? PrincipalId,
    string? PrincipalDisplayName,
    string PrincipalType,
    string? ResourceId,
    string ResourceDisplayName,
    string? AppRoleId,
    DateTimeOffset? CreatedDateTime,
    
    bool IsGraphAssignment
);