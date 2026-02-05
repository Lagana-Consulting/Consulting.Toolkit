using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class SignInSignalsCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public SignInSignalsCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var signals = new Dictionary<string, SignInSignalRecord>();
        var checkpoint = new CollectorCheckpoint("SignInSignals");

        try
        {
            progress?.Report("📥 Fetching sign-in logs (last 30 days)...");

            // Get sign-in logs from last 30 days
            var thirtyDaysAgo = DateTimeOffset.UtcNow.AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ");
            
            var signIns = await _graphClient.ExecuteAsync(
                async client => await client.AuditLogs.SignIns.Request()
                    .Filter($"createdDateTime ge {thirtyDaysAgo}")
                    .Top(999)
                    .OrderBy("createdDateTime desc")
                    .GetAsync(cancellationToken),
                cancellationToken);

            // Process sign-in logs to find most recent per user
            foreach (var signIn in signIns.CurrentPage)
            {
                if (string.IsNullOrEmpty(signIn.UserId))
                    continue;

                var signInDate = signIn.CreatedDateTime;
                
                if (!signals.ContainsKey(signIn.UserId) || 
                    (signInDate.HasValue && signInDate > signals[signIn.UserId].LastSignInDateTime))
                {
                    var daysSinceLastSignIn = signInDate.HasValue
                        ? (int)(DateTimeOffset.UtcNow - signInDate.Value).TotalDays
                        : int.MaxValue;

                    signals[signIn.UserId] = new SignInSignalRecord(
                        Id: signIn.UserId,
                        DisplayName: signIn.UserDisplayName,
                        UserPrincipalName: signIn.UserPrincipalName,
                        UserType: null, // Not available in sign-in logs
                        AccountEnabled: true, // Assumed if signing in
                        
                        LastSignInDateTime: signInDate,
                        LastNonInteractiveSignInDateTime: null,
                        DaysSinceLastSignIn: daysSinceLastSignIn == int.MaxValue ? null : daysSinceLastSignIn,
                        
                        IsStale: daysSinceLastSignIn > 90,
                        NeverSignedIn: false, // They signed in if in the logs
                        IsInactive: daysSinceLastSignIn > 180
                    );
                }

                checkpoint.ItemsProcessed++;
                if (checkpoint.ItemsProcessed % 100 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} sign-in events...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            
            var staleCount = signals.Values.Count(s => s.IsStale);
            var inactiveCount = signals.Values.Count(s => s.IsInactive);
            
            progress?.Report($"✅ Analyzed {signals.Count} users from sign-in logs ({staleCount} stale, {inactiveCount} inactive)");

            return new CollectorResult(
                WorkloadKey: "entra.signInSignals",
                Success: true,
                ItemCount: signals.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected sign-in data for {signals.Count} users (last 30 days)",
                Data: signals.Values.ToList(),
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = "Permission denied";
            
            return new CollectorResult(
                WorkloadKey: "entra.signInSignals",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need AuditLog.Read.All + Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.ErrorMessage = ex.Message;
            
            return new CollectorResult(
                WorkloadKey: "entra.signInSignals",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: $"❌ Error: {ex.Message}",
                Data: null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record SignInSignalRecord(
    string Id,
    string? DisplayName,
    string? UserPrincipalName,
    string? UserType,
    bool AccountEnabled,
    
    DateTimeOffset? LastSignInDateTime,
    DateTimeOffset? LastNonInteractiveSignInDateTime,
    int? DaysSinceLastSignIn,
    
    bool IsStale,
    bool NeverSignedIn,
    bool IsInactive
);