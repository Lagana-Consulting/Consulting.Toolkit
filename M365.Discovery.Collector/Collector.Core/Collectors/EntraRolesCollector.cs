using Collector.Graph;
using Microsoft.Graph;

namespace Collector.Core.Collectors;

public sealed class EntraRolesCollector : IWorkloadCollector
{
    private readonly ResilientGraphClient _graphClient;

    public EntraRolesCollector(ResilientGraphClient graphClient)
    {
        _graphClient = graphClient ?? throw new ArgumentNullException(nameof(graphClient));
    }

    public async Task<CollectorResult> CollectAsync(
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var roles = new List<EntraRoleRecord>();
        var checkpoint = new CollectorCheckpoint("EntraRoles");

        try
        {
            progress?.Report("📥 Fetching Entra directory roles and assignments...");

            // Get directory role templates
            await foreach (var roleTemplate in _graphClient.PageAllAsync<Microsoft.Graph.DirectoryRoleTemplate, IGraphServiceDirectoryRoleTemplatesCollectionPage>(
                client => client.DirectoryRoleTemplates.Request()
                    .Select("id,displayName,description")
                    .GetAsync(cancellationToken),
                cancellationToken))
            {
                // Get active directory role from template
                DirectoryRole? activeRole = null;
                try
                {
                    var rolesWithTemplate = await _graphClient.ExecuteAsync(
                        async client => await client.DirectoryRoles.Request()
                            .Filter($"roleTemplateId eq '{roleTemplate.Id}'")
                            .GetAsync(cancellationToken),
                        cancellationToken);

                    activeRole = rolesWithTemplate.FirstOrDefault();
                }
                catch
                {
                    // Role not activated, skip
                }

                int memberCount = 0;
                if (activeRole != null)
                {
                    try
                    {
                        var members = await _graphClient.ExecuteAsync(
                            async client => await client.DirectoryRoles[activeRole.Id].Members.Request()
                                .GetAsync(cancellationToken),
                            cancellationToken);
                        memberCount = members.Count;
                    }
                    catch
                    {
                        // Unable to read members
                    }
                }

                roles.Add(new EntraRoleRecord(
                    RoleTemplateId: roleTemplate.Id,
                    DisplayName: roleTemplate.DisplayName,
                    Description: roleTemplate.Description,
                    IsActivated: activeRole != null,
                    ActiveRoleId: activeRole?.Id,
                    MemberCount: memberCount
                ));

                checkpoint.ItemsProcessed++;

                if (checkpoint.ItemsProcessed % 10 == 0)
                {
                    progress?.Report($"  ↳ Processed {checkpoint.ItemsProcessed} roles...");
                }
            }

            checkpoint.Status = CheckpointStatus.Completed;
            progress?.Report($"✅ Collected {roles.Count} directory roles ({roles.Count(r => r.IsActivated)} activated)");

            return new CollectorResult(
                WorkloadKey: "entra.roles",
                Success: true,
                ItemCount: roles.Count,
                ConfidenceLevel: ConfidenceLevel.Authoritative,
                Message: $"Collected {roles.Count} directory roles",
                Data: roles,
                Checkpoint: checkpoint
            );
        }
        catch (ServiceException ex) when (ex.StatusCode == System.Net.HttpStatusCode.Forbidden)
        {
            checkpoint.Status = CheckpointStatus.Failed;

            return new CollectorResult(
                WorkloadKey: "entra.roles",
                Success: false,
                ItemCount: 0,
                ConfidenceLevel: ConfidenceLevel.Unavailable,
                Message: "❌ Permission denied - need RoleManagement.Read.All or Directory.Read.All",
                Data: null,
                Checkpoint: checkpoint
            );
        }
    }
}

public sealed record EntraRoleRecord(
    string RoleTemplateId,
    string? DisplayName,
    string? Description,
    bool IsActivated,
    string? ActiveRoleId,
    int MemberCount
);