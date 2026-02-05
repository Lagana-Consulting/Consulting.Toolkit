using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core;

public sealed class PreflightService
{
    private readonly ResilientGraphClient _graphClient;
    private CapabilityMatrix? _cachedMatrix;

    public PreflightService(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    /// <summary>
    /// Run preflight check: authenticate, detect permissions, test Graph connectivity
    /// </summary>
    public async Task<PreflightReport> RunPreflightAsync(TokenInfo tokenInfo, CancellationToken cancellationToken = default)
    {
        var detector = new PermissionDetector(tokenInfo);
        _cachedMatrix = detector.DetectCapabilities();

        // Sanity check: call /organization
        var orgTestResult = await TestOrganizationEndpointAsync(cancellationToken);

        return new PreflightReport(
            TenantId: tokenInfo.TenantId,
            Username: tokenInfo.Username,
            GrantedScopes: tokenInfo.GrantedScopes,
            CapabilityMatrix: _cachedMatrix,
            OrganizationEndpointAccessible: orgTestResult.Success,
            OrganizationTestMessage: orgTestResult.Message
        );
    }

    /// <summary>
    /// Check capability for a specific workload
    /// </summary>
    public Task<PreflightResult> CheckAsync(DiscoveryContext context, string workloadKey)
    {
        if (_cachedMatrix == null)
        {
            return Task.FromResult(new PreflightResult(
                PreflightStatus.Unknown,
                "Preflight not yet run. Call RunPreflightAsync first."));
        }

        var status = _cachedMatrix.GetStatus(workloadKey);
        var preflightStatus = status switch
        {
            CapabilityStatus.Available => PreflightStatus.Available,
            CapabilityStatus.Partial => PreflightStatus.Partial,
            CapabilityStatus.Blocked => PreflightStatus.Blocked,
            _ => PreflightStatus.Unknown
        };

        var message = status switch
        {
            CapabilityStatus.Available => "✅ Capability available",
            CapabilityStatus.Partial => "⚠ Partial access - limited data available",
            CapabilityStatus.Blocked => $"❌ Blocked - missing required scopes",
            _ => "Unknown capability status"
        };

        return Task.FromResult(new PreflightResult(preflightStatus, message));
    }

    private async Task<(bool Success, string Message)> TestOrganizationEndpointAsync(CancellationToken cancellationToken)
    {
        try
        {
            var org = await _graphClient.ExecuteAsync(
                async client => await client.Organization.Request().GetAsync(cancellationToken),
                cancellationToken);

            if (org?.Count > 0)
            {
                var orgName = org[0].DisplayName ?? "Unknown";
                return (true, $"✅ Connected to organization: {orgName}");
            }

            return (false, "⚠ Organization endpoint returned empty response");
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            return (false, "❌ Forbidden (403) - check Organization.Read.All or Directory.Read.All permission");
        }
        catch (ServiceException ex)
        {
            return (false, $"❌ Graph error: {ex.StatusCode} - {ex.Message}");
        }
        catch (Exception ex)
        {
            return (false, $"❌ Unexpected error: {ex.Message}");
        }
    }
}

public sealed record PreflightReport(
    string TenantId,
    string Username,
    string[] GrantedScopes,
    CapabilityMatrix CapabilityMatrix,
    bool OrganizationEndpointAccessible,
    string OrganizationTestMessage
);
