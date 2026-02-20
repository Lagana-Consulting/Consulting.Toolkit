using System.Reflection;
using System.Text;

namespace Collector.Core.Output;

public sealed class CsvWriter
{
    public string Write<T>(IEnumerable<T> records)
    {
        var recordList = records.ToList();
        if (!recordList.Any())
            return string.Empty;

        var properties = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => p.CanRead)
            .OrderBy(p => p.MetadataToken) // Preserve declaration order
            .ToArray();

        var sb = new StringBuilder();

        // Write header
        sb.AppendLine(string.Join(",", properties.Select(p => EscapeCsvValue(p.Name))));

        // Write rows
        foreach (var record in recordList)
        {
            var values = properties.Select(p =>
            {
                var value = p.GetValue(record);
                return FormatValue(value);
            });

            sb.AppendLine(string.Join(",", values.Select(EscapeCsvValue)));
        }

        return sb.ToString();
    }

    public string WriteHeaderOnly<T>()
    {
        var properties = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => p.CanRead)
            .OrderBy(p => p.MetadataToken)
            .ToArray();

        if (properties.Length == 0)
            return string.Empty;

        return string.Join(",", properties.Select(p => EscapeCsvValue(p.Name))) + Environment.NewLine;
    }

    private static string FormatValue(object? value)
    {
        if (value == null)
            return string.Empty;

        return value switch
        {
            DateTimeOffset dto => dto.ToString("yyyy-MM-dd HH:mm:ss"),
            DateTime dt => dt.ToString("yyyy-MM-dd HH:mm:ss"),
            bool b => b.ToString(),
            string s => s,
            Array arr => string.Join("; ", arr.Cast<object>().Select(o => o?.ToString() ?? "")),
            IEnumerable<string> strEnum => string.Join("; ", strEnum),
            _ => value.ToString() ?? string.Empty
        };
    }

    private static string EscapeCsvValue(string value)
    {
        if (string.IsNullOrEmpty(value))
            return string.Empty;

        // If value contains comma, quote, or newline, wrap in quotes and escape internal quotes
        if (value.Contains(',') || value.Contains('"') || value.Contains('\n') || value.Contains('\r'))
        {
            return $"\"{value.Replace("\"", "\"\"")}\"";
        }

        return value;
    }
}
