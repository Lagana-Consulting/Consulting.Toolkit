using System.Globalization;
using System.Text;
using System.Text.Json;
using Collector.Core;

namespace Collector.Export;

public sealed class CsvExportService
{
    public async Task WriteRunMetadataAsync(DiscoveryContext ctx, IEnumerable<string> selectedWorkloadKeys)
    {
        var obj = new
        {
            RunName = ctx.RunName,
            OutputFolder = ctx.OutputFolder,
            CollectedAtUtc = DateTime.UtcNow,
            SelectedWorkloads = selectedWorkloadKeys.ToArray(),
            Version = "starter-1.0"
        };

        var json = JsonSerializer.Serialize(obj, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(Path.Combine(ctx.OutputFolder, "RunMetadata.json"), json, Encoding.UTF8);
    }

    public async Task WriteAccessGapsAsync(DiscoveryContext ctx, IReadOnlyList<AccessGapRow> gaps)
    {
        var path = Path.Combine(ctx.OutputFolder, "AccessGaps.csv");
        var headers = new[] { "Dataset", "Metric", "Status", "Reason", "Needed" };

        await WriteCsvAsync(path, headers, gaps.Select(g => new Dictionary<string,string>
        {
            ["Dataset"] = g.Dataset,
            ["Metric"] = g.Metric,
            ["Status"] = g.Status,
            ["Reason"] = g.Reason,
            ["Needed"] = g.Needed
        }));
    }

    public async Task WriteSummaryAsync(DiscoveryContext ctx, IEnumerable<string> selectedWorkloadKeys)
    {
        var rows = selectedWorkloadKeys.Select(k => new Dictionary<string,string>
        {
            ["WorkloadKey"] = k,
            ["CollectedAtUtc"] = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture),
            ["Confidence"] = "Stubbed",
            ["Notes"] = "Replace stubbed collectors with real Graph-based data collection."
        }).ToList();

        await WriteCsvAsync(Path.Combine(ctx.OutputFolder, "Summary.csv"),
            new[] { "WorkloadKey", "CollectedAtUtc", "Confidence", "Notes" },
            rows);
    }

    public async Task WriteSampleWorkloadCsvAsync(DiscoveryContext ctx, string workloadKey, IReadOnlyList<Dictionary<string,string>> rows)
    {
        string fileName = workloadKey switch
        {
            "entra.directory" => "Entra_Directory.csv",
            "reports.onedrive" => "OneDrive_Usage.csv",
            "reports.sharepoint" => "SharePoint_Usage.csv",
            "reports.teams" => "Teams_Usage.csv",
            _ => $"{SanitizeFileName(workloadKey)}.csv"
        };

        var path = Path.Combine(ctx.OutputFolder, fileName);

        // Determine headers from union of keys
        var headers = rows.SelectMany(r => r.Keys).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        await WriteCsvAsync(path, headers, rows);
    }

    private static string SanitizeFileName(string name)
    {
        var invalidChars = Path.GetInvalidFileNameChars();
        return string.Create(name.Length, (name, invalidChars), (span, state) =>
        {
            state.name.AsSpan().CopyTo(span);
            for (int i = 0; i < span.Length; i++)
            {
                if (Array.IndexOf(state.invalidChars, span[i]) >= 0)
                    span[i] = '_';
            }
        });
    }

    private static async Task WriteCsvAsync(string path, IReadOnlyList<string> headers, IEnumerable<Dictionary<string,string>> rows)
    {
        await using var stream = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read);
        await using var writer = new StreamWriter(stream, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));

        await writer.WriteLineAsync(string.Join(",", headers.Select(Escape)));

        foreach (var row in rows)
        {
            var values = headers.Select(h => row.TryGetValue(h, out var v) ? v : "").Select(Escape);
            await writer.WriteLineAsync(string.Join(",", values));
        }
    }

    private static string Escape(string s)
    {
        if (string.IsNullOrEmpty(s))
            return s;

        if (s.Contains('"'))
            s = s.Replace("\"", "\"\"");

        if (s.Contains(',') || s.Contains('\n') || s.Contains('\r') || s.Contains('"'))
            return $"\"{s}\"";

        return s;
    }
}
