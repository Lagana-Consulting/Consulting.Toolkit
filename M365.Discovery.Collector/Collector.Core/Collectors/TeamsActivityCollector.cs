using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class TeamsActivityCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public TeamsActivityCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var checkpoint = new CollectorCheckpoint("TeamsActivity");
        var reportDays = context.ReportDays;

        try
        {
            progress?.Report($"📊 Fetching Teams user activity report (last {reportDays} days)...");

            var reportStream = await _graphClient.ExecuteAsync(
                async client =>
                {
                    var request = client.Reports.GetTeamsUserActivityUserDetail(context.ReportPeriod).Request();
                    return await request.GetAsync(cancellationToken);
                },
                cancellationToken);

            var activity = new List<TeamsActivityRecord>();

            using (var reader = new StreamReader(reportStream))
            {
                // Skip header
                await reader.ReadLineAsync();

                while (!reader.EndOfStream)
                {
                    var line = await reader.ReadLineAsync();
                    if (string.IsNullOrWhiteSpace(line)) continue;

                    var fields = line.Split(',');
                    if (fields.Length < 26) continue;

                    // Correct mapping based on actual API response:
                    // Report Refresh Date, User Id, User Principal Name, Last Activity Date, Is Deleted, Deleted Date,
                    // Assigned Products, Team Chat Message Count, Private Chat Message Count, Call Count, Meeting Count,
                    // Meetings Organized Count, Meetings Attended Count, Ad Hoc Meetings Organized Count,
                    // Ad Hoc Meetings Attended Count, Scheduled One-time Meetings Organized Count,
                    // Scheduled One-time Meetings Attended Count, Scheduled Recurring Meetings Organized Count,
                    // Scheduled Recurring Meetings Attended Count, Audio Duration, Video Duration, Screen Share Duration,
                    // Audio Duration In Seconds, Video Duration In Seconds, Screen Share Duration In Seconds,
                    // Has Other Action, Urgent Messages, Post Messages, Tenant Display Name,
                    // Shared Channel Tenant Display Names, Reply Messages, Is Licensed, Report Period
                    activity.Add(new TeamsActivityRecord(
                        ReportRefreshDate: ParseDateSafe(fields[0]),
                        UserId: fields[1],
                        UserPrincipalName: fields[2],
                        LastActivityDate: ParseDateSafe(fields[3]),
                        IsDeleted: ParseBoolSafe(fields[4]),
                        DeletedDate: ParseDateSafe(fields[5]),
                        AssignedProducts: fields[6],
                        TeamChatMessageCount: ParseLongSafe(fields[7]),
                        PrivateChatMessageCount: ParseLongSafe(fields[8]),
                        CallCount: ParseLongSafe(fields[9]),
                        MeetingCount: ParseLongSafe(fields[10]),
                        MeetingsOrganizedCount: ParseLongSafe(fields[11]),
                        MeetingsAttendedCount: ParseLongSafe(fields[12]),
                        AdHocMeetingsOrganizedCount: ParseLongSafe(fields[13]),
                        AdHocMeetingsAttendedCount: ParseLongSafe(fields[14]),
                        ScheduledOnetimeMeetingsOrganizedCount: ParseLongSafe(fields[15]),
                        ScheduledOnetimeMeetingsAttendedCount: ParseLongSafe(fields[16]),
                        ScheduledRecurringMeetingsOrganizedCount: ParseLongSafe(fields[17]),
                        ScheduledRecurringMeetingsAttendedCount: ParseLongSafe(fields[18]),
                        AudioDuration: fields[19],
                        VideoDuration: fields[20],
                        ScreenShareDuration: fields[21],
                        AudioDurationInSeconds: ParseLongSafe(fields[22]),
                        VideoDurationInSeconds: ParseLongSafe(fields[23]),
                        ScreenShareDurationInSeconds: ParseLongSafe(fields[24]),
                        HasOtherAction: fields[25],
                        UrgentMessages: fields.Length > 26 ? ParseLongSafe(fields[26]) : 0,
                        PostMessages: fields.Length > 27 ? ParseLongSafe(fields[27]) : 0,
                        TenantDisplayName: fields.Length > 28 ? fields[28] : null,
                        SharedChannelTenantDisplayNames: fields.Length > 29 ? fields[29] : null,
                        ReplyMessages: fields.Length > 30 ? ParseLongSafe(fields[30]) : 0,
                        IsLicensed: fields.Length > 31 ? fields[31] : null,
                        ReportPeriodDays: fields.Length > 32 ? ParseIntSafe(fields[32]) : reportDays
                    ));

                    checkpoint.ItemsProcessed++;

                    if (checkpoint.ItemsProcessed % 100 == 0)
                    {
                        progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} users...");
                    }
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected Teams activity for {activity.Count} users");

            return new CollectorResult(
                WorkloadKey: "reports.teams",
                Success: true,
                ItemCount: activity.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected Teams activity for {activity.Count} users",
                Data: activity,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;

            return new CollectorResult(
                WorkloadKey: "reports.teams",
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

public sealed record TeamsActivityRecord(
    DateTimeOffset? ReportRefreshDate,
    string UserId,
    string UserPrincipalName,
    DateTimeOffset? LastActivityDate,
    bool IsDeleted,
    DateTimeOffset? DeletedDate,
    string AssignedProducts,
    long TeamChatMessageCount,
    long PrivateChatMessageCount,
    long CallCount,
    long MeetingCount,
    long MeetingsOrganizedCount,
    long MeetingsAttendedCount,
    long AdHocMeetingsOrganizedCount,
    long AdHocMeetingsAttendedCount,
    long ScheduledOnetimeMeetingsOrganizedCount,
    long ScheduledOnetimeMeetingsAttendedCount,
    long ScheduledRecurringMeetingsOrganizedCount,
    long ScheduledRecurringMeetingsAttendedCount,
    string AudioDuration,
    string VideoDuration,
    string ScreenShareDuration,
    long AudioDurationInSeconds,
    long VideoDurationInSeconds,
    long ScreenShareDurationInSeconds,
    string HasOtherAction,
    long UrgentMessages,
    long PostMessages,
    string? TenantDisplayName,
    string? SharedChannelTenantDisplayNames,
    long ReplyMessages,
    string? IsLicensed,
    int ReportPeriodDays
);
