namespace Collector.Core;

public sealed record AccessGapRow(
    string Dataset,
    string Metric,
    string Status,
    string Reason,
    string Needed
);
