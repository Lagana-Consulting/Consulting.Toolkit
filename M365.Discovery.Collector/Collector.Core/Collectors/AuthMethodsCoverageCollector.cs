// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using System.Text.Json;
using Collector.Graph;

namespace Collector.Core.Collectors;

public sealed class AuthMethodsCoverageCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public AuthMethodsCoverageCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var rows = new List<AuthMethodCoverageRecord>();
        var checkpoint = new CollectorCheckpoint("AuthMethodsCoverage");

        try
        {
            progress?.Report("Fetching authentication methods coverage...");

            var nextLink = "/reports/authenticationMethods/userRegistrationDetails?$top=100";
            while (!string.IsNullOrWhiteSpace(nextLink))
            {
                var page = await GetPageAsync(nextLink, cancellationToken);

                if (!page.RootElement.TryGetProperty("value", out var valueElement) || valueElement.ValueKind != JsonValueKind.Array)
                {
                    break;
                }

                foreach (var item in valueElement.EnumerateArray())
                {
                    var methods = ReadStringArray(item, "methodsRegistered");

                    rows.Add(new AuthMethodCoverageRecord(
                        Id: ReadString(item, "id"),
                        UserPrincipalName: ReadString(item, "userPrincipalName"),
                        UserDisplayName: ReadString(item, "userDisplayName"),
                        UserType: ReadString(item, "userType"),
                        IsAdmin: ReadBool(item, "isAdmin"),
                        IsSsprRegistered: ReadBool(item, "isSsprRegistered"),
                        IsSsprEnabled: ReadBool(item, "isSsprEnabled"),
                        IsSsprCapable: ReadBool(item, "isSsprCapable"),
                        IsMfaRegistered: ReadBool(item, "isMfaRegistered"),
                        IsMfaCapable: ReadBool(item, "isMfaCapable"),
                        IsPasswordlessCapable: ReadBool(item, "isPasswordlessCapable"),
                        IsSystemPreferredAuthenticationMethodEnabled: ReadBool(item, "isSystemPreferredAuthenticationMethodEnabled"),
                        LastUpdatedDateTime: ReadDateTimeOffset(item, "lastUpdatedDateTime"),
                        DefaultMfaMethod: ReadString(item, "defaultMfaMethod"),
                        MethodsRegisteredCount: methods.Length,
                        MethodsRegistered: methods.Length == 0 ? null : string.Join(";", methods)
                    ));

                    checkpoint.ItemsProcessed++;
                    if (checkpoint.ItemsProcessed % 250 == 0)
                    {
                        progress?.Report($"  Processed {checkpoint.ItemsProcessed} users...");
                    }
                }

                nextLink = page.RootElement.TryGetProperty("@odata.nextLink", out var nextElement)
                    ? nextElement.GetString()
                    : null;
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"Collected {rows.Count} authentication methods coverage rows");

            return new CollectorResult(
                WorkloadKey: "entra.authMethods",
                Success: true,
                ItemCount: rows.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {rows.Count} auth methods coverage rows",
                Data: rows,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex) when (IsForbidden(ex))
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "entra.authMethods",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "Permission denied - need Reports.Read.All + User.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;

            return new CollectorResult(
                WorkloadKey: "entra.authMethods",
                Success: false,
                ItemCount: rows.Count,
                ConfidenceLevel: rows.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"Partial failure after {rows.Count} items: {ex.Message}",
                Data: rows.Count > 0 ? rows : null,
                Checkpoint: checkpoint
            );
        }
    }

    private async Task<JsonDocument> GetPageAsync(string nextLink, CancellationToken cancellationToken)
    {
        return await _graphClient.ExecuteAsync(async client =>
        {
            var url = nextLink.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                ? nextLink
                : $"{client.BaseUrl.TrimEnd('/')}/{nextLink.TrimStart('/')}";

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            await client.AuthenticationProvider.AuthenticateRequestAsync(request);

            using var response = await client.HttpProvider.SendAsync(request);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException($"Graph request failed ({(int)response.StatusCode}): {body}");
            }

            return JsonDocument.Parse(body);
        }, cancellationToken);
    }

    private static bool IsForbidden(Exception ex)
    {
        var message = ex.Message ?? string.Empty;
        return message.Contains("(403)") || message.Contains("Forbidden", StringComparison.OrdinalIgnoreCase);
    }

    private static string? ReadString(JsonElement obj, string name)
    {
        return obj.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String
            ? p.GetString()
            : null;
    }

    private static bool? ReadBool(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var p)) return null;
        return p.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null
        };
    }

    private static DateTimeOffset? ReadDateTimeOffset(JsonElement obj, string name)
    {
        var raw = ReadString(obj, name);
        if (string.IsNullOrWhiteSpace(raw)) return null;
        return DateTimeOffset.TryParse(raw, out var dto) ? dto : null;
    }

    private static string[] ReadStringArray(JsonElement obj, string name)
    {
        if (!obj.TryGetProperty(name, out var p) || p.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<string>();
        }

        return p.EnumerateArray()
            .Where(x => x.ValueKind == JsonValueKind.String)
            .Select(x => x.GetString())
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Select(x => x!)
            .ToArray();
    }
}

public sealed record AuthMethodCoverageRecord(
    string? Id,
    string? UserPrincipalName,
    string? UserDisplayName,
    string? UserType,
    bool? IsAdmin,
    bool? IsSsprRegistered,
    bool? IsSsprEnabled,
    bool? IsSsprCapable,
    bool? IsMfaRegistered,
    bool? IsMfaCapable,
    bool? IsPasswordlessCapable,
    bool? IsSystemPreferredAuthenticationMethodEnabled,
    DateTimeOffset? LastUpdatedDateTime,
    string? DefaultMfaMethod,
    int MethodsRegisteredCount,
    string? MethodsRegistered
);
