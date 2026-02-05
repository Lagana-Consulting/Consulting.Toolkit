using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class OrganizationCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public OrganizationCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var checkpoint = new CollectorCheckpoint("Organization");

        try
        {
            progress?.Report("📥 Fetching organization details...");

            // Get organization
            var orgs = await _graphClient.ExecuteAsync(
                async client => await client.Organization.Request()
                    .Select("id,displayName,verifiedDomains,assignedPlans,technicalNotificationMails,createdDateTime")
                    .GetAsync(cancellationToken),
                cancellationToken);

            var org = orgs.FirstOrDefault();
            if (org == null)
            {
                return new CollectorResult(
                    WorkloadKey: "organization.basic",
                    Success: false,
                    ItemCount: 0,
                    ConfidenceLevel: ConfidenceLevel.Unavailable,
                    Message: "❌ No organization data returned",
                    Data: null,
                    Checkpoint: checkpoint
                );
            }

            // Get domains
            progress?.Report("📥 Fetching domains...");
            var domains = new List<string>();
            await foreach (var domain in _graphClient.PageAllAsync<Microsoft.Graph.Domain, IGraphServiceDomainsCollectionPage>(
                client => client.Domains.Request().GetAsync(cancellationToken),
                cancellationToken))
            {
                domains.Add(domain.Id);
            }

            // Get license SKUs
            progress?.Report("📥 Fetching license SKUs...");
            var licenses = new List<LicenseSkuRecord>();
            await foreach (var sku in _graphClient.PageAllAsync<Microsoft.Graph.SubscribedSku, IGraphServiceSubscribedSkusCollectionPage>(
                client => client.SubscribedSkus.Request().GetAsync(cancellationToken),
                cancellationToken))
            {
                licenses.Add(new LicenseSkuRecord(
                    SkuId: sku.SkuId?.ToString() ?? string.Empty,
                    SkuPartNumber: sku.SkuPartNumber,
                    ConsumedUnits: sku.ConsumedUnits ?? 0,
                    PrepaidUnitsEnabled: sku.PrepaidUnits?.Enabled ?? 0,
                    PrepaidUnitsSuspended: sku.PrepaidUnits?.Suspended ?? 0,
                    PrepaidUnitsWarning: sku.PrepaidUnits?.Warning ?? 0,
                    CapabilityStatus: sku.CapabilityStatus
                ));
            }

            var orgData = new OrganizationData(
                OrganizationId: org.Id,
                DisplayName: org.DisplayName,
                VerifiedDomains: org.VerifiedDomains?.Select(d => d.Name).ToArray() ?? Array.Empty<string>(),
                AllDomains: domains.ToArray(),
                TechnicalNotificationMails: org.TechnicalNotificationMails?.ToArray() ?? Array.Empty<string>(),
                CreatedDateTime: org.CreatedDateTime,
                LicenseSkus: licenses.ToArray()
            );

            checkpoint.ItemsProcessed = 1 + domains.Count + licenses.Count;
            checkpoint.Status = CheckpointStatus.Completed;

            progress?.Report($"✅ Collected organization details ({domains.Count} domains, {licenses.Count} SKUs)");

            return new CollectorResult(
                WorkloadKey: "organization.basic",
                Success: true,
                ItemCount: 1,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected organization with {domains.Count} domains and {licenses.Count} license SKUs",
                Data: orgData,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;

            return new CollectorResult(
                WorkloadKey: "organization.basic",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need Organization.Read.All or Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record OrganizationData(
    string OrganizationId,
    string? DisplayName,
    string[] VerifiedDomains,
    string[] AllDomains,
    string[] TechnicalNotificationMails,
    DateTimeOffset? CreatedDateTime,
    LicenseSkuRecord[] LicenseSkus
);

public sealed record LicenseSkuRecord(
    string SkuId,
    string? SkuPartNumber,
    int ConsumedUnits,
    int PrepaidUnitsEnabled,
    int PrepaidUnitsSuspended,
    int PrepaidUnitsWarning,
    string? CapabilityStatus
);