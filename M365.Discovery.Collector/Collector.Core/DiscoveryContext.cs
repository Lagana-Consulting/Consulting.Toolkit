namespace Collector.Core;

public sealed record DiscoveryContext
{
    public static readonly int[] SupportedReportDays = { 7, 30, 90, 180 };
    public const int DefaultReportDays = 7;

    public DiscoveryContext(string outputFolder, string runName, int reportDays = DefaultReportDays)
    {
        OutputFolder = outputFolder;
        RunName = runName;
        ReportDays = NormalizeReportDays(reportDays);
    }

    public string OutputFolder { get; }
    public string RunName { get; }
    public int ReportDays { get; }
    public string ReportPeriod => $"D{ReportDays}";

    public static int NormalizeReportDays(int reportDays) =>
        SupportedReportDays.Contains(reportDays) ? reportDays : DefaultReportDays;
}
