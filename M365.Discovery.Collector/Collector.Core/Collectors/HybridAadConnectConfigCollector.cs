// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using System.Text.Json;
using Collector.Graph;

namespace Collector.Core.Collectors;

public sealed class HybridAadConnectConfigCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public HybridAadConnectConfigCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var checkpoint = new CollectorCheckpoint("HybridAadConnectConfig");
        var rows = new List<HybridAadConnectConfigRecord>();

        try
        {
            progress?.Report("Fetching hybrid AAD Connect configuration...");

            var orgDoc = await GetJsonAsync("/organization?$select=id,displayName,onPremisesSyncEnabled", cancellationToken);
            if (orgDoc == null)
            {
                throw new InvalidOperationException("Graph request returned no organization payload.");
            }
            JsonDocument? syncDoc = null;
            var syncAccessDenied = false;

            try
            {
                syncDoc = await GetJsonAsync("/directory/onPremisesSynchronization", cancellationToken, suppressNotFound: true);
            }
            catch (Exception ex) when (IsAuthDenied(ex))
            {
                // Keep organization-level signal even if onPremisesSynchronization endpoint is denied.
                syncAccessDenied = true;
                progress?.Report("onPremisesSynchronization access denied; returning partial hybrid configuration.");
            }

            var org = orgDoc.RootElement.TryGetProperty("value", out var orgArr) && orgArr.ValueKind == JsonValueKind.Array
                ? orgArr.EnumerateArray().FirstOrDefault()
                : default;

            var tenantId = ReadString(org, "id");
            var organizationName = ReadString(org, "displayName");
            var onPremisesSyncEnabled = ReadBool(org, "onPremisesSyncEnabled");

            bool? hasSyncConfig = null;
            string? syncConfigurationVersion = null;
            string? accidentalDeletionPrevention = null;
            string? syncFeatures = null;
            string? syncAgents = null;
            string? syncRawJson = null;

            if (syncDoc != null)
            {
                var root = syncDoc.RootElement;
                hasSyncConfig = true;
                syncConfigurationVersion = ReadString(root, "configurationVersion");
                accidentalDeletionPrevention = ReadAdditionalDataValue(root, "accidentalDeletionPrevention");
                syncFeatures = ReadAdditionalDataValue(root, "features");
                syncAgents = ReadAdditionalDataValue(root, "synchronizationAgents");
                syncRawJson = root.ToString();
            }
            else
            {
                hasSyncConfig = false;
            }

            rows.Add(new HybridAadConnectConfigRecord(
                TenantId: tenantId,
                OrganizationName: organizationName,
                OnPremisesSyncEnabled: onPremisesSyncEnabled,
                HasOnPremisesSynchronizationConfig: hasSyncConfig,
                SyncConfigurationVersion: syncConfigurationVersion,
                AccidentalDeletionPrevention: accidentalDeletionPrevention,
                SyncFeaturesJson: syncFeatures,
                SyncAgentsJson: syncAgents,
                RawOnPremisesSynchronizationJson: syncRawJson
            ));

            checkpoint.ItemsProcessed = rows.Count;
            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"Collected {rows.Count} hybrid AAD Connect config row(s)");

            return new CollectorResult(
                WorkloadKey: "hybrid.aadConnectConfig",
                Success: !syncAccessDenied,
                ItemCount: rows.Count,
                ConfidenceLevel: syncAccessDenied ? ConfidenceLevel.Partial : ConfidenceLevel.Authoritative,
                Message: syncAccessDenied
                    ? "Partial access: collected organization hybrid signal, but /directory/onPremisesSynchronization was denied (requires OnPremDirectorySynchronization.Read.All and supported Entra role in delegated mode)."
                    : $"Collected {rows.Count} hybrid AAD Connect config row(s)",
                Data: rows,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex) when (IsAuthDenied(ex))
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "hybrid.aadConnectConfig",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "Permission denied - need OnPremDirectorySynchronization.Read.All + Organization.Read.All (delegated also requires a supported Entra role).",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;

            return new CollectorResult(
                WorkloadKey: "hybrid.aadConnectConfig",
                Success: false,
                ItemCount: rows.Count,
                ConfidenceLevel: rows.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"Partial failure after {rows.Count} items: {ex.Message}",
                Data: rows.Count > 0 ? rows : null,
                Checkpoint: checkpoint
            );
        }
    }

    private async Task<JsonDocument?> GetJsonAsync(string relativePath, CancellationToken cancellationToken, bool suppressNotFound = false)
    {
        return await _graphClient.ExecuteAsync(async client =>
        {
            var url = $"{client.BaseUrl.TrimEnd('/')}/{relativePath.TrimStart('/')}";
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            await client.AuthenticationProvider.AuthenticateRequestAsync(request);

            using var response = await client.HttpProvider.SendAsync(request);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);

            if (suppressNotFound && response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                return null;
            }

            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException($"Graph request failed ({(int)response.StatusCode}): {body}");
            }

            return JsonDocument.Parse(body);
        }, cancellationToken);
    }

    private static string? ReadString(JsonElement obj, string name)
    {
        if (obj.ValueKind != JsonValueKind.Object) return null;
        return obj.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String
            ? p.GetString()
            : null;
    }

    private static bool? ReadBool(JsonElement obj, string name)
    {
        if (obj.ValueKind != JsonValueKind.Object) return null;
        if (!obj.TryGetProperty(name, out var p)) return null;
        return p.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null
        };
    }

    private static string? ReadAdditionalDataValue(JsonElement obj, string propertyName)
    {
        if (obj.ValueKind != JsonValueKind.Object) return null;
        if (!obj.TryGetProperty(propertyName, out var p)) return null;
        return p.ValueKind switch
        {
            JsonValueKind.String => p.GetString(),
            JsonValueKind.Null => null,
            _ => p.ToString()
        };
    }

    private static bool IsAuthDenied(Exception ex)
    {
        var message = ex.Message ?? string.Empty;
        return message.Contains("(403)") ||
               message.Contains("Forbidden", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("Authorization_RequestDenied", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("Insufficient privileges", StringComparison.OrdinalIgnoreCase);
    }
}

public sealed record HybridAadConnectConfigRecord(
    string? TenantId,
    string? OrganizationName,
    bool? OnPremisesSyncEnabled,
    bool? HasOnPremisesSynchronizationConfig,
    string? SyncConfigurationVersion,
    string? AccidentalDeletionPrevention,
    string? SyncFeaturesJson,
    string? SyncAgentsJson,
    string? RawOnPremisesSynchronizationJson
);
