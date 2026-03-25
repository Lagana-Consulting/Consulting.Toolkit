using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class SharePointUsageCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public SharePointUsageCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var checkpoint = new CollectorCheckpoint("SharePointUsage");
        var reportDays = context.ReportDays;

        try
        {
            progress?.Report($"📊 Fetching SharePoint site usage report (last {reportDays} days)...");

            var reportStream = await _graphClient.ExecuteAsync(
                async client =>
                {
                    var request = client.Reports.GetSharePointSiteUsageDetail(context.ReportPeriod).Request();
                    return await request.GetAsync(cancellationToken);
                },
                cancellationToken);

            var usage = new List<SharePointSiteUsageRecord>();

            using (var reader = new StreamReader(reportStream))
            {
                // Skip header
                await reader.ReadLineAsync();

                while (!reader.EndOfStream)
                {
                    var line = await reader.ReadLineAsync();
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    var fields = line.Split(',');
                    if (fields.Length < 13) continue;

                    // Correct mapping: Report Refresh Date, Site Id, Site URL, Owner Display Name, Is Deleted,
                    // Last Activity Date, File Count, Active File Count, Page View Count, Visited Page Count,
                    // Storage Used (Byte), Storage Allocated (Byte), Root Web Template, Owner Principal Name, Report Period
                    usage.Add(new SharePointSiteUsageRecord(
                        ReportRefreshDate: ParseDateSafe(fields[0]),
                        SiteId: fields[1],
                        SiteUrl: fields[2],
                        OwnerDisplayName: fields[3],
                        IsDeleted: ParseBoolSafe(fields[4]),
                        LastActivityDate: ParseDateSafe(fields[5]),
                        FileCount: ParseLongSafe(fields[6]),
                        ActiveFileCount: ParseLongSafe(fields[7]),
                        PageViewCount: ParseLongSafe(fields[8]),
                        VisitedPageCount: ParseLongSafe(fields[9]),
                        StorageUsedBytes: ParseLongSafe(fields[10]),
                        StorageAllocatedBytes: ParseLongSafe(fields[11]),
                        RootWebTemplate: fields[12],
                        OwnerPrincipalName: fields.Length > 13 ? fields[13] : null,
                        ReportPeriodDays: fields.Length > 14 ? ParseIntSafe(fields[14]) : reportDays
                    ));

                    checkpoint.ItemsProcessed++;

                    if (checkpoint.ItemsProcessed % 100 == 0)
                    {
                        progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} sites...");
                    }
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected SharePoint usage for {usage.Count} sites");

            return new CollectorResult(
                WorkloadKey: "reports.sharepoint",
                Success: true,
                ItemCount: usage.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected SharePoint usage for {usage.Count} sites",
                Data: usage,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;

            return new CollectorResult(
                WorkloadKey: "reports.sharepoint",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Reports.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;

            return new CollectorResult(
                WorkloadKey: "reports.sharepoint",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: $"❌ Error: {ex.Message}",
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

public sealed record SharePointSiteUsageRecord(
    DateTimeOffset? ReportRefreshDate,
    string SiteId,
    string SiteUrl,
    string OwnerDisplayName,
    bool IsDeleted,
    DateTimeOffset? LastActivityDate,
    long FileCount,
    long ActiveFileCount,
    long PageViewCount,
    long VisitedPageCount,
    long StorageUsedBytes,
    long StorageAllocatedBytes,
    string RootWebTemplate,
    string? OwnerPrincipalName,
    int ReportPeriodDays
);
