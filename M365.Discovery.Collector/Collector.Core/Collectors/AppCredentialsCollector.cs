// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class AppCredentialsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public AppCredentialsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var credentials = new List<AppCredentialRecord>();
        var checkpoint = new CollectorCheckpoint("AppCredentials");

        try
        {
            progress?.Report("📥 Fetching app registrations & service principals with credentials...");

            // Process Application Registrations
            await foreach (var app in _graphClient.PageAllAsync<Microsoft.Graph.Application, IGraphServiceApplicationsCollectionPage>(
                client => client.Applications.Request()
                    .Select("id,appId,displayName,passwordCredentials,keyCredentials,createdDateTime")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                if (app.PasswordCredentials != null)
                {
                    foreach (var cred in app.PasswordCredentials)
                    {
                        var daysUntilExpiry = cred.EndDateTime.HasValue
                            ? (int)(cred.EndDateTime.Value - DateTimeOffset.UtcNow).TotalDays
                            : int.MaxValue;

                        credentials.Add(new AppCredentialRecord(
                            ObjectId: app.Id,
                            AppId: app.AppId,
                            DisplayName: app.DisplayName,
                            ObjectType: "Application",
                            CredentialType: "Secret",
                            KeyId: cred.KeyId?.ToString(),
                            DisplayNameHint: cred.DisplayName,
                            StartDateTime: cred.StartDateTime,
                            EndDateTime: cred.EndDateTime,
                            DaysUntilExpiry: daysUntilExpiry,
                            
                            IsExpired: daysUntilExpiry < 0,
                            IsExpiringSoon: daysUntilExpiry >= 0 && daysUntilExpiry <= 90,
                            IsExpiredOrExpiringSoon: daysUntilExpiry < 90
                        ));
                    }
                }

                if (app.KeyCredentials != null)
                {
                    foreach (var cred in app.KeyCredentials)
                    {
                        var daysUntilExpiry = cred.EndDateTime.HasValue
                            ? (int)(cred.EndDateTime.Value - DateTimeOffset.UtcNow).TotalDays
                            : int.MaxValue;

                        credentials.Add(new AppCredentialRecord(
                            ObjectId: app.Id,
                            AppId: app.AppId,
                            DisplayName: app.DisplayName,
                            ObjectType: "Application",
                            CredentialType: "Certificate",
                            KeyId: cred.KeyId?.ToString(),
                            DisplayNameHint: cred.DisplayName,
                            StartDateTime: cred.StartDateTime,
                            EndDateTime: cred.EndDateTime,
                            DaysUntilExpiry: daysUntilExpiry,
                            
                            IsExpired: daysUntilExpiry < 0,
                            IsExpiringSoon: daysUntilExpiry >= 0 && daysUntilExpiry <= 90,
                            IsExpiredOrExpiringSoon: daysUntilExpiry < 90
                        ));
                    }
                }

                checkpoint.ItemsProcessed++;
            }

            // Process Service Principals
            await foreach (var sp in _graphClient.PageAllAsync<Microsoft.Graph.ServicePrincipal, IGraphServiceServicePrincipalsCollectionPage>(
                client => client.ServicePrincipals.Request()
                    .Select("id,appId,displayName,passwordCredentials,keyCredentials")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                if (sp.PasswordCredentials != null)
                {
                    foreach (var cred in sp.PasswordCredentials)
                    {
                        var daysUntilExpiry = cred.EndDateTime.HasValue
                            ? (int)(cred.EndDateTime.Value - DateTimeOffset.UtcNow).TotalDays
                            : int.MaxValue;

                        credentials.Add(new AppCredentialRecord(
                            ObjectId: sp.Id,
                            AppId: sp.AppId,
                            DisplayName: sp.DisplayName,
                            ObjectType: "ServicePrincipal",
                            CredentialType: "Secret",
                            KeyId: cred.KeyId?.ToString(),
                            DisplayNameHint: cred.DisplayName,
                            StartDateTime: cred.StartDateTime,
                            EndDateTime: cred.EndDateTime,
                            DaysUntilExpiry: daysUntilExpiry,
                            
                            IsExpired: daysUntilExpiry < 0,
                            IsExpiringSoon: daysUntilExpiry >= 0 && daysUntilExpiry <= 90,
                            IsExpiredOrExpiringSoon: daysUntilExpiry < 90
                        ));
                    }
                }

                if (sp.KeyCredentials != null)
                {
                    foreach (var cred in sp.KeyCredentials)
                    {
                        var daysUntilExpiry = cred.EndDateTime.HasValue
                            ? (int)(cred.EndDateTime.Value - DateTimeOffset.UtcNow).TotalDays
                            : int.MaxValue;

                        credentials.Add(new AppCredentialRecord(
                            ObjectId: sp.Id,
                            AppId: sp.AppId,
                            DisplayName: sp.DisplayName,
                            ObjectType: "ServicePrincipal",
                            CredentialType: "Certificate",
                            KeyId: cred.KeyId?.ToString(),
                            DisplayNameHint: cred.DisplayName,
                            StartDateTime: cred.StartDateTime,
                            EndDateTime: cred.EndDateTime,
                            DaysUntilExpiry: daysUntilExpiry,
                            
                            IsExpired: daysUntilExpiry < 0,
                            IsExpiringSoon: daysUntilExpiry >= 0 && daysUntilExpiry <= 90,
                            IsExpiredOrExpiringSoon: daysUntilExpiry < 90
                        ));
                    }
                }

                checkpoint.ItemsProcessed++;
            }

            checkpoint.Status = CheckpointStatus.Completed;
            
            var expiredCount = credentials.Count(c => c.IsExpired);
            var expiringSoonCount = credentials.Count(c => c.IsExpiringSoon);
            
            progress?.Report($"✅ Collected {credentials.Count} credentials ({expiredCount} expired, {expiringSoonCount} expiring within 90 days)");

            return new CollectorResult(
                WorkloadKey: "entra.appCredentials",
                Success: true,
                ItemCount: credentials.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {credentials.Count} app credentials",
                Data: credentials,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.appCredentials",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Application.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.appCredentials",
                Success: false,
                ItemCount: credentials.Count,
                ConfidenceLevel: credentials.Count > 0 ? ConfidenceLevel.Partial : ConfidenceLevel.Unavailable,
                Message: $"⚠ Partial failure after {credentials.Count} items: {ex.Message}",
                Data: credentials.Count > 0 ? credentials : null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record AppCredentialRecord(
    string ObjectId,
    string AppId,
    string? DisplayName,
    string ObjectType,
    string CredentialType,
    string? KeyId,
    string? DisplayNameHint,
    DateTimeOffset? StartDateTime,
    DateTimeOffset? EndDateTime,
    int DaysUntilExpiry,
    
    bool IsExpired,
    bool IsExpiringSoon,
    bool IsExpiredOrExpiringSoon
);