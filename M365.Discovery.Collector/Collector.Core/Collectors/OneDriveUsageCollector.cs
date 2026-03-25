using Collector.Graph;
using Microsoft.Graph;
using System.Text;

namespace Collector.Core.Collectors;

public sealed class OneDriveUsageCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public OneDriveUsageCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var checkpoint = new CollectorCheckpoint("OneDriveUsage");
        var reportDays = context.ReportDays;

        try
        {
            progress?.Report($"📊 Fetching OneDrive usage report (last {reportDays} days)...");

            // Graph reports API: /reports/getOneDriveUsageAccountDetail(period='D7')
            var reportStream = await _graphClient.ExecuteAsync(
                async client =>
                {
                    var request = client.Reports.GetOneDriveUsageAccountDetail(context.ReportPeriod).Request();
                    return await request.GetAsync(cancellationToken);
                },
                cancellationToken);

            var usage = new List<OneDriveUsageRecord>();

            using (var reader = new StreamReader(reportStream))
            {
                // Skip header
                await reader.ReadLineAsync();

                while (!reader.EndOfStream)
                {
                    var line = await reader.ReadLineAsync();
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    var fields = line.Split(',');
                    if (fields.Length < 11) continue;

                    // Correct mapping: Report Refresh Date, Site Id, Site URL, Owner Display Name, Is Deleted,
                    // Last Activity Date, File Count, Active File Count, Storage Used (Byte), 
                    // Storage Allocated (Byte), Owner Principal Name, Report Period
                    usage.Add(new OneDriveUsageRecord(
                        ReportRefreshDate: ParseDateSafe(fields[0]),
                        SiteId: fields[1],
                        SiteUrl: fields[2],
                        OwnerDisplayName: fields[3],
                        IsDeleted: ParseBoolSafe(fields[4]),
                        LastActivityDate: ParseDateSafe(fields[5]),
                        FileCount: ParseLongSafe(fields[6]),
                        ActiveFileCount: ParseLongSafe(fields[7]),
                        StorageUsedBytes: ParseLongSafe(fields[8]),
                        StorageAllocatedBytes: ParseLongSafe(fields[9]),
                        OwnerPrincipalName: fields[10],
                        ReportPeriodDays: fields.Length > 11 ? ParseIntSafe(fields[11]) : reportDays
                    ));

                    checkpoint.ItemsProcessed++;

                    if (checkpoint.ItemsProcessed % 100 == 0)
                    {
                        progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} accounts...");
                    }
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected OneDrive usage for {usage.Count} accounts");

            return new CollectorResult(
                WorkloadKey: "reports.onedrive",
                Success: true,
                ItemCount: usage.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected OneDrive usage for {usage.Count} accounts",
                Data: usage,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;

            return new CollectorResult(
                WorkloadKey: "reports.onedrive",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Reports.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
    }

    private static DateTimeOffset? ParseDateSafe(string value) =>
        DateTimeOffset.TryParse(value, out var date) ? date : null;

    private static long ParseLongSafe(string value) =>
        long.TryParse(value, out var number) ? number : 0;

    private static int ParseIntSafe(string value) =>
        int.TryParse(value, out var number) ? number : 0;

    private static bool ParseBoolSafe(string value) =>
        bool.TryParse(value, out var result) && result;
}

public sealed record OneDriveUsageRecord(
    DateTimeOffset? ReportRefreshDate,
    string SiteId,
    string SiteUrl,
    string OwnerDisplayName,
    bool IsDeleted,
    DateTimeOffset? LastActivityDate,
    long FileCount,
    long ActiveFileCount,
    long StorageUsedBytes,
    long StorageAllocatedBytes,
    string OwnerPrincipalName,
    int ReportPeriodDays
);
