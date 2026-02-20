using System.Text.Json;
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class ConditionalAccessCollector : IWorkloadCollector
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    private readonly ResilientGraphClient _graphClient;

    public ConditionalAccessCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var policies = new List<ConditionalAccessPolicyRecord>();
        var checkpoint = new CollectorCheckpoint("ConditionalAccess");

        try
        {
            progress?.Report("Fetching Conditional Access policies...");

            var page = await _graphClient.ExecuteAsync(
                async client => await client.Identity.ConditionalAccess.Policies.Request().GetAsync(cancellationToken),
                cancellationToken);

            while (page != null)
            {
                foreach (var policy in page.CurrentPage)
                {
                    var includedUsers = policy.Conditions?.Users?.IncludeUsers?.ToList() ?? new List<string>();
                    var excludedUsers = policy.Conditions?.Users?.ExcludeUsers?.ToList() ?? new List<string>();
                    var includedGroups = policy.Conditions?.Users?.IncludeGroups?.ToList() ?? new List<string>();
                    var excludedGroups = policy.Conditions?.Users?.ExcludeGroups?.ToList() ?? new List<string>();
                    var includedRoles = policy.Conditions?.Users?.IncludeRoles?.ToList() ?? new List<string>();
                    var excludedRoles = policy.Conditions?.Users?.ExcludeRoles?.ToList() ?? new List<string>();

                    var includedApps = policy.Conditions?.Applications?.IncludeApplications?.ToList() ?? new List<string>();
                    var excludedApps = policy.Conditions?.Applications?.ExcludeApplications?.ToList() ?? new List<string>();
                    var includedUserActions = policy.Conditions?.Applications?.IncludeUserActions?.ToList() ?? new List<string>();

                    var grantControls = policy.GrantControls?.BuiltInControls?.Select(c => c.ToString()).ToList() ?? new List<string>();
                    var customAuthFactors = policy.GrantControls?.CustomAuthenticationFactors?.ToList() ?? new List<string>();
                    var termsOfUse = policy.GrantControls?.TermsOfUse?.ToList() ?? new List<string>();

                    var includedLocations = policy.Conditions?.Locations?.IncludeLocations?.ToList() ?? new List<string>();
                    var excludedLocations = policy.Conditions?.Locations?.ExcludeLocations?.ToList() ?? new List<string>();
                    var includedPlatforms = policy.Conditions?.Platforms?.IncludePlatforms?.Select(p => p.ToString()).ToList() ?? new List<string>();
                    var excludedPlatforms = policy.Conditions?.Platforms?.ExcludePlatforms?.Select(p => p.ToString()).ToList() ?? new List<string>();
                    var includedClientApps = policy.Conditions?.ClientAppTypes?.Select(t => t.ToString()).ToList() ?? new List<string>();

                    var signInRiskLevels = policy.Conditions?.SignInRiskLevels?.Select(x => x.ToString()).ToList() ?? new List<string>();
                    var userRiskLevels = policy.Conditions?.UserRiskLevels?.Select(x => x.ToString()).ToList() ?? new List<string>();

                    var includeAllUsers = includedUsers.Any(x => x.Equals("All", StringComparison.OrdinalIgnoreCase));
                    var includeAllApps = includedApps.Any(x => x.Equals("All", StringComparison.OrdinalIgnoreCase));

                    var authStrengthDisplayName = GetAdditionalDataValue(policy.GrantControls?.AdditionalData, "authenticationStrength.displayName");
                    var authStrengthRequirements = GetAdditionalDataValue(policy.GrantControls?.AdditionalData, "authenticationStrength.requirementsSatisfied");

                    var hasSignInFrequency = policy.SessionControls?.SignInFrequency != null;
                    var hasPersistentBrowser = policy.SessionControls?.PersistentBrowser != null;
                    var hasCloudAppSecurity = policy.SessionControls?.CloudAppSecurity != null;
                    var hasDisableResilienceDefaults = policy.SessionControls?.DisableResilienceDefaults != null;

                    policies.Add(new ConditionalAccessPolicyRecord(
                        Id: policy.Id,
                        DisplayName: policy.DisplayName,
                        State: policy.State?.ToString() ?? "Unknown",
                        CreatedDateTime: policy.CreatedDateTime,
                        ModifiedDateTime: policy.ModifiedDateTime,

                        IncludedUserCount: includedUsers.Count,
                        ExcludedUserCount: excludedUsers.Count,
                        IncludedGroupCount: includedGroups.Count,
                        ExcludedGroupCount: excludedGroups.Count,
                        IncludeAllUsers: includeAllUsers,

                        IncludedAppCount: includedApps.Count,
                        ExcludedAppCount: excludedApps.Count,
                        IncludeAllApps: includeAllApps,

                        GrantControls: string.Join(", ", grantControls),
                        RequireMultiFactor: grantControls.Contains("mfa", StringComparer.OrdinalIgnoreCase),
                        RequireCompliantDevice: grantControls.Contains("compliantDevice", StringComparer.OrdinalIgnoreCase),
                        RequireHybridJoin: grantControls.Contains("domainJoinedDevice", StringComparer.OrdinalIgnoreCase),

                        IncludedLocationCount: includedLocations.Count,
                        ExcludedLocationCount: excludedLocations.Count,
                        HasNamedLocations: includedLocations.Count > 0 || excludedLocations.Count > 0,

                        HasPlatformConditions: policy.Conditions?.Platforms != null,
                        HasDeviceStateConditions: policy.Conditions?.Devices != null,

                        SessionControls: policy.SessionControls != null ? "Configured" : "None",

                        IncludedUsers: Join(includedUsers),
                        ExcludedUsers: Join(excludedUsers),
                        IncludedGroups: Join(includedGroups),
                        ExcludedGroups: Join(excludedGroups),
                        IncludedRoles: Join(includedRoles),
                        ExcludedRoles: Join(excludedRoles),
                        IncludedApplications: Join(includedApps),
                        ExcludedApplications: Join(excludedApps),
                        IncludedUserActions: Join(includedUserActions),
                        IncludedLocations: Join(includedLocations),
                        ExcludedLocations: Join(excludedLocations),
                        IncludedPlatforms: Join(includedPlatforms),
                        ExcludedPlatforms: Join(excludedPlatforms),
                        IncludedClientAppTypes: Join(includedClientApps),
                        SignInRiskLevels: Join(signInRiskLevels),
                        UserRiskLevels: Join(userRiskLevels),
                        GrantOperator: policy.GrantControls?.Operator?.ToString(),
                        BuiltInControls: Join(grantControls),
                        CustomAuthenticationFactors: Join(customAuthFactors),
                        TermsOfUse: Join(termsOfUse),
                        AuthenticationStrengthDisplayName: authStrengthDisplayName,
                        AuthenticationStrengthRequirementsSatisfied: authStrengthRequirements,
                        HasSignInFrequencySessionControl: hasSignInFrequency,
                        HasPersistentBrowserSessionControl: hasPersistentBrowser,
                        HasCloudAppSecuritySessionControl: hasCloudAppSecurity,
                        HasDisableResilienceDefaultsSessionControl: hasDisableResilienceDefaults,
                        ConditionsJson: ToJson(policy.Conditions),
                        GrantControlsJson: ToJson(policy.GrantControls),
                        SessionControlsJson: ToJson(policy.SessionControls)
                    ));

                    checkpoint.ItemsProcessed++;
                    if (checkpoint.ItemsProcessed % 5 == 0)
                    {
                        progress?.Report($"  Processed {checkpoint.ItemsProcessed} policies...");
                    }
                }

                if (page.NextPageRequest == null)
                {
                    break;
                }

                page = await _graphClient.ExecuteAsync(
                    async _ => await page.NextPageRequest.GetAsync(cancellationToken),
                    cancellationToken);
            }

            checkpoint.Status = CheckpointStatus.Completed;
            var enabledCount = policies.Count(p => p.State.Equals("enabled", StringComparison.OrdinalIgnoreCase));

            progress?.Report($"Collected {policies.Count} Conditional Access policies ({enabledCount} enabled)");

            return new CollectorResult(
                WorkloadKey: "entra.conditionalAccess",
                Success: true,
                ItemCount: policies.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {policies.Count} CA policies",
                Data: policies,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";

            return new CollectorResult(
                WorkloadKey: "entra.conditionalAccess",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "Permission denied - need Policy.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;

            return new CollectorResult(
                WorkloadKey: "entra.conditionalAccess",
                Success: false,
                ItemCount: policies.Count,
                ConfidenceLevel: policies.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"Partial failure after {policies.Count} items: {ex.Message}",
                Data: policies.Count > 0 ? policies : null,
                Checkpoint: checkpoint
            );
        }
    }

    private static string? ToJson(object? value)
    {
        if (value == null)
        {
            return null;
        }

        try
        {
            return JsonSerializer.Serialize(value, JsonOptions);
        }
        catch
        {
            return null;
        }
    }

    private static string? Join(IEnumerable<string> values)
    {
        var items = values.Where(v => !string.IsNullOrWhiteSpace(v)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        return items.Length == 0 ? null : string.Join(";", items);
    }

    private static string? GetAdditionalDataValue(IDictionary<string, object>? additionalData, string path)
    {
        if (additionalData == null || additionalData.Count == 0)
        {
            return null;
        }

        try
        {
            object? current = additionalData;
            foreach (var segment in path.Split('.'))
            {
                if (current is IDictionary<string, object> dictObj && dictObj.TryGetValue(segment, out var nextObj))
                {
                    current = nextObj;
                    continue;
                }

                if (current is IDictionary<string, JsonElement> dictJson && dictJson.TryGetValue(segment, out var nextJson))
                {
                    current = nextJson;
                    continue;
                }

                if (current is JsonElement el)
                {
                    if (el.ValueKind == JsonValueKind.Object && el.TryGetProperty(segment, out var child))
                    {
                        current = child;
                        continue;
                    }
                    return null;
                }

                return null;
            }

            return current switch
            {
                null => null,
                JsonElement je when je.ValueKind == JsonValueKind.String => je.GetString(),
                JsonElement je => je.ToString(),
                _ => current.ToString()
            };
        }
        catch
        {
            return null;
        }
    }
}

public sealed record ConditionalAccessPolicyRecord(
    string Id,
    string DisplayName,
    string State,
    DateTimeOffset? CreatedDateTime,
    DateTimeOffset? ModifiedDateTime,

    int IncludedUserCount,
    int ExcludedUserCount,
    int IncludedGroupCount,
    int ExcludedGroupCount,
    bool IncludeAllUsers,

    int IncludedAppCount,
    int ExcludedAppCount,
    bool IncludeAllApps,

    string GrantControls,
    bool RequireMultiFactor,
    bool RequireCompliantDevice,
    bool RequireHybridJoin,

    int IncludedLocationCount,
    int ExcludedLocationCount,
    bool HasNamedLocations,

    bool HasPlatformConditions,
    bool HasDeviceStateConditions,

    string SessionControls,

    string? IncludedUsers,
    string? ExcludedUsers,
    string? IncludedGroups,
    string? ExcludedGroups,
    string? IncludedRoles,
    string? ExcludedRoles,
    string? IncludedApplications,
    string? ExcludedApplications,
    string? IncludedUserActions,
    string? IncludedLocations,
    string? ExcludedLocations,
    string? IncludedPlatforms,
    string? ExcludedPlatforms,
    string? IncludedClientAppTypes,
    string? SignInRiskLevels,
    string? UserRiskLevels,
    string? GrantOperator,
    string? BuiltInControls,
    string? CustomAuthenticationFactors,
    string? TermsOfUse,
    string? AuthenticationStrengthDisplayName,
    string? AuthenticationStrengthRequirementsSatisfied,
    bool HasSignInFrequencySessionControl,
    bool HasPersistentBrowserSessionControl,
    bool HasCloudAppSecuritySessionControl,
    bool HasDisableResilienceDefaultsSessionControl,
    string? ConditionsJson,
    string? GrantControlsJson,
    string? SessionControlsJson
);
