// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core;

public sealed class PreflightService
{
    private readonly ResilientGraphClient _graphClient;
    private CapabilityMatrix? _cachedMatrix;
    private TokenInfo? _cachedTokenInfo;

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
        _cachedTokenInfo = tokenInfo;

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
        var source = _cachedMatrix.GetSource(workloadKey);
        var requiredPermissions = _cachedMatrix.GetRequiredPermissionsForCapability(workloadKey);
        var requiredDisplay = requiredPermissions.Length > 0
            ? string.Join("; ", requiredPermissions)
            : "No mapping available";
        var missingTokens = _cachedMatrix.GetMissingPermissionTokens(workloadKey);
        var missingTokenDisplay = missingTokens.Length > 0
            ? string.Join(", ", missingTokens)
            : "none";
        var sourceDisplay = source switch
        {
            CapabilityPermissionSource.Delegated => "delegated",
            CapabilityPermissionSource.Application => "application",
            CapabilityPermissionSource.Both => "delegated+application",
            _ => "unknown"
        };
        var reasonCode = GetReasonCode(status, source, missingTokens);

        var preflightStatus = status switch
        {
            CapabilityStatus.Available => PreflightStatus.Available,
            CapabilityStatus.Partial => PreflightStatus.Partial,
            CapabilityStatus.Blocked => PreflightStatus.Blocked,
            _ => PreflightStatus.Unknown
        };

        var message = status switch
        {
            CapabilityStatus.Available => $"✅ Capability available (source: {sourceDisplay})",
            CapabilityStatus.Partial => $"⚠ Partial access (reason: {reasonCode}, source: {sourceDisplay}) - likely missing: {requiredDisplay} | missing tokens: {missingTokenDisplay}",
            CapabilityStatus.Blocked => $"❌ Blocked (reason: {reasonCode}, source: {sourceDisplay}) - missing permissions: {requiredDisplay} | missing tokens: {missingTokenDisplay}",
            _ => "Unknown capability status"
        };

        if (workloadKey.Equals("hybrid.aadConnectConfig", StringComparison.OrdinalIgnoreCase) &&
            _cachedTokenInfo?.AuthMode == AuthMode.InteractiveDelegated)
        {
            message += " | note: delegated path also requires a supported Entra admin role for /directory/onPremisesSynchronization.";
        }

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

    private string GetReasonCode(CapabilityStatus status, CapabilityPermissionSource source, string[] missingTokens)
    {
        if (status == CapabilityStatus.Available)
        {
            return "available";
        }

        if (_cachedTokenInfo == null)
        {
            return "unknown";
        }

        if (_cachedTokenInfo.AuthMode == AuthMode.AppOnly && _cachedTokenInfo.ApplicationRoles.Length == 0)
        {
            return "consent_not_granted";
        }

        if (_cachedTokenInfo.AuthMode == AuthMode.InteractiveDelegated &&
            _cachedTokenInfo.DelegatedScopes.Length == 0 &&
            source == CapabilityPermissionSource.Unknown)
        {
            return "mode_mismatch";
        }

        if (missingTokens.Length > 0)
        {
            return "missing_permissions";
        }

        return "unknown";
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
