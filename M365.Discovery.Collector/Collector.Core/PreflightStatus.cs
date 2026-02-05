namespace Collector.Core;

public enum PreflightStatus
{
    Unknown = 0,
    Available = 1,
    Partial = 2,
    Blocked = 3
}

public sealed record PreflightResult(PreflightStatus Status, string Message);
