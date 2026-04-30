// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class ExchangeMailboxUsageCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public ExchangeMailboxUsageCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var checkpoint = new CollectorCheckpoint("ExchangeMailboxUsage");
        var reportDays = context.ReportDays;

        try
        {
            progress?.Report($"📊 Fetching Exchange mailbox usage report (last {reportDays} days)...");

            // Graph reports API: /reports/getMailboxUsageDetail(period='D7')
            var reportStream = await _graphClient.ExecuteAsync(
                async client =>
                {
                    var request = client.Reports.GetMailboxUsageDetail(context.ReportPeriod).Request();
                    return await request.GetAsync(cancellationToken);
                },
                cancellationToken);

            var usage = new List<ExchangeMailboxUsageRecord>();

            using (var reader = new StreamReader(reportStream))
            {
                // Skip header
                await reader.ReadLineAsync();

                while (!reader.EndOfStream)
                {
                    var line = await reader.ReadLineAsync();
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    var fields = line.Split(',');
                    if (fields.Length < 15) continue;

                    // Correct mapping: Report Refresh Date, User Principal Name, Display Name, Is Deleted, 
                    // Deleted Date, Created Date, Last Activity Date, Item Count, Storage Used (Byte), 
                    // Issue Warning Quota (Byte), Prohibit Send Quota (Byte), Prohibit Send/Receive Quota (Byte), 
                    // Deleted Item Count, Deleted Item Size (Byte), Deleted Item Quota (Byte), Has Archive, Report Period
                    usage.Add(new ExchangeMailboxUsageRecord(
                        ReportRefreshDate: ParseDateSafe(fields[0]),
                        UserPrincipalName: fields[1],
                        DisplayName: fields[2],
                        IsDeleted: ParseBoolSafe(fields[3]),
                        DeletedDate: ParseDateSafe(fields[4]),
                        CreatedDate: ParseDateSafe(fields[5]),
                        LastActivityDate: ParseDateSafe(fields[6]),
                        ItemCount: ParseLongSafe(fields[7]),
                        StorageUsedBytes: ParseLongSafe(fields[8]),
                        IssueWarningQuotaBytes: ParseLongSafe(fields[9]),
                        ProhibitSendQuotaBytes: ParseLongSafe(fields[10]),
                        ProhibitSendReceiveQuotaBytes: ParseLongSafe(fields[11]),
                        DeletedItemCount: ParseLongSafe(fields[12]),
                        DeletedItemSizeBytes: ParseLongSafe(fields[13]),
                        DeletedItemQuotaBytes: ParseLongSafe(fields[14]),
                        HasArchive: ParseBoolSafe(fields[15]),
                        ReportPeriodDays: fields.Length > 16 ? ParseIntSafe(fields[16]) : reportDays
                    ));

                    checkpoint.ItemsProcessed++;

                    if (checkpoint.ItemsProcessed % 100 == 0)
                    {
                        progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} mailboxes...");
                    }
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            
            var archiveCount = usage.Count(u => u.HasArchive);
            
            progress?.Report($"✅ Collected Exchange mailbox usage for {usage.Count} mailboxes");
            if (archiveCount > 0)
            {
                progress?.Report($"   📦 {archiveCount} mailboxes have archives enabled");
            }

            return new CollectorResult(
                WorkloadKey: "reports.exchange",
                Success: true,
                ItemCount: usage.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected Exchange mailbox usage for {usage.Count} mailboxes ({archiveCount} with archives)",
                Data: usage,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;

            return new CollectorResult(
                WorkloadKey: "reports.exchange",
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

public sealed record ExchangeMailboxUsageRecord(
    DateTimeOffset? ReportRefreshDate,
    string UserPrincipalName,
    string DisplayName,
    bool IsDeleted,
    DateTimeOffset? DeletedDate,
    DateTimeOffset? CreatedDate,
    DateTimeOffset? LastActivityDate,
    long ItemCount,
    long StorageUsedBytes,
    long IssueWarningQuotaBytes,
    long ProhibitSendQuotaBytes,
    long ProhibitSendReceiveQuotaBytes,
    long DeletedItemCount,
    long DeletedItemSizeBytes,
    long DeletedItemQuotaBytes,
    bool HasArchive,
    int ReportPeriodDays
);
