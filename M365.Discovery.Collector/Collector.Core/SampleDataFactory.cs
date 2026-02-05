using System.Collections.Generic;

namespace Collector.Core;

public static class SampleDataFactory
{
    // Placeholder rows to prove out end-to-end CSV export + GUI flow.
    // Replace with real collectors that call Graph and stream results.
    public static IReadOnlyList<Dictionary<string, string>> CreateSampleRows(string workloadKey)
        => workloadKey switch
        {
            "entra.directory" => new List<Dictionary<string, string>>
            {
                new() { ["ObjectType"]="User", ["DisplayName"]="Ada Lovelace", ["UPN"]="ada@example.com", ["Id"]="00000000-0000-0000-0000-000000000001" },
                new() { ["ObjectType"]="Group", ["DisplayName"]="Migration Team", ["Mail"]="migration@example.com", ["Id"]="00000000-0000-0000-0000-000000000002" },
            },
            "reports.onedrive" => new List<Dictionary<string, string>>
            {
                new() { ["Report"]="OneDriveUsageAccountDetail", ["Period"]="D30", ["StorageUsedGB"]="1234.56", ["FileCount"]="987654" },
            },
            "reports.sharepoint" => new List<Dictionary<string, string>>
            {
                new() { ["Report"]="SharePointSiteUsageDetail", ["Period"]="D30", ["StorageUsedGB"]="4321.00", ["FileCount"]="1234567" },
            },
            "reports.teams" => new List<Dictionary<string, string>>
            {
                new() { ["Report"]="TeamsUserActivityUserDetail", ["Period"]="D30", ["ActiveUsers"]="2500", ["Meetings"]="120000" },
            },
            _ => new List<Dictionary<string, string>>
            {
                new() { ["Info"]="No sample defined for this workload." }
            }
        };
}
