// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
namespace Collector.Core;

public interface IWorkloadCollector
{
    Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default);
}

public sealed record CollectorResult(
    string WorkloadKey,
    bool Success,
    int ItemCount,
    ConfidenceLevel ConfidenceLevel,
    string Message,
    object? Data,
    CollectorCheckpoint Checkpoint
);

public enum ConfidenceLevel
{
    Authoritative,  // Direct from API
    Derived,        // Computed from authoritative
    Estimated,      // Sampling/extrapolation
    Partial,        // Incomplete due to errors
    Unavailable     // Missing permissions
}

public sealed class CollectorCheckpoint
{
    public string CollectorName { get; }
    public int ItemsProcessed { get; set; }
    public CheckpointStatus Status { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTimeOffset StartedAt { get; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? CompletedAt { get; set; }

    public CollectorCheckpoint(string collectorName)
    {
        CollectorName = collectorName;
        Status = CheckpointStatus.InProgress;
    }
}

public enum CheckpointStatus
{
    InProgress,
    Completed,
    Failed
}