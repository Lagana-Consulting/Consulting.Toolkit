using System.Globalization;
using System.Text;
using System.Text.Json;
using Collector.Graph;

namespace Collector.Core.Output;

public sealed class OutputManager
{
    private readonly DiscoveryContext _context;
    private readonly List<CollectorResult> _results = new();
    private readonly RunMetadata _metadata;

    public OutputManager(DiscoveryContext context, PreflightReport preflightReport)
    {
        _context = context ?? throw new ArgumentNullException(nameof(context));
        _metadata = new RunMetadata(
            context.RunName,
            DateTimeOffset.UtcNow,
            preflightReport.TenantId,
            preflightReport.Username,
            preflightReport.GrantedScopes,
            preflightReport.CapabilityMatrix.Capabilities
                .ToDictionary(k => k.Key, v => v.Value.ToString())
        );

        EnsureOutputDirectory();
    }

    public void AddResult(CollectorResult result)
    {
        _results.Add(result);
    }

    public async Task FinalizeAsync(CancellationToken cancellationToken = default)
    {
        _metadata.CompletedAt = DateTimeOffset.UtcNow;
        _metadata.TotalCollectors = _results.Count;
        _metadata.SuccessfulCollectors = _results.Count(r => r.Success);
        _metadata.FailedCollectors = _results.Count(r => !r.Success);
        _metadata.TotalItemsCollected = _results.Sum(r => r.ItemCount);

        // Export all collector data to CSVs
        await ExportCollectorDataAsync(cancellationToken);

        // Generate access gaps report
        await GenerateAccessGapsReportAsync(cancellationToken);

        // Generate summary
        await GenerateSummaryAsync(cancellationToken);

        // 🆕 Generate migration risk analysis report
        await GenerateMigrationRiskReportAsync(cancellationToken);

        // Write metadata
        await WriteMetadataAsync(cancellationToken);

        Console.WriteLine($"\n📁 All outputs written to: {_context.OutputFolder}");
    }

    private async Task ExportCollectorDataAsync(CancellationToken cancellationToken)
    {
        foreach (var result in _results)
        {
            var fileName = GetCsvFileName(result.WorkloadKey);
            var filePath = Path.Combine(_context.OutputFolder, fileName);

            try
            {
                if (result.ItemCount == 0)
                {
                    if (IsCsvWorkload(result.WorkloadKey))
                    {
                        await WriteHeaderOnlyCsvAsync(filePath, result.WorkloadKey, cancellationToken);
                        await WriteLegacyAliasCsvsAsync(filePath, result.WorkloadKey, cancellationToken);
                        Console.WriteLine($"  ✅ Exported: {fileName} (0 items; header-only)");
                    }
                    continue;
                }

                if (result.Data == null)
                    continue;

                await WriteCsvAsync(filePath, result.Data, result.WorkloadKey, cancellationToken);
                await WriteLegacyAliasCsvsAsync(filePath, result.WorkloadKey, cancellationToken);
                Console.WriteLine($"  ✅ Exported: {fileName} ({result.ItemCount} items)");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"  ❌ Failed to export {fileName}: {ex.Message}");
                _metadata.Errors.Add($"Export failed for {fileName}: {ex.Message}");
            }
        }
    }

    private async Task WriteCsvAsync(string filePath, object data, string workloadKey, CancellationToken cancellationToken)
    {
        var csvWriter = new CsvWriter();

        var csvContent = workloadKey switch
        {
            // V1 Collectors
            "entra.users" => csvWriter.Write((IEnumerable<Collectors.EntraUserRecord>)data),
            "entra.groups" => csvWriter.Write((IEnumerable<Collectors.EntraGroupRecord>)data),
            "entra.m365groups" => csvWriter.Write((IEnumerable<Collectors.M365GroupRecord>)data),
            "entra.apps" => csvWriter.Write((IEnumerable<Collectors.EntraApplicationRecord>)data),
            "entra.servicePrincipals" => csvWriter.Write((IEnumerable<Collectors.EntraServicePrincipalRecord>)data),
            "entra.roles" => csvWriter.Write((IEnumerable<Collectors.EntraRoleRecord>)data),
            "reports.onedrive" => csvWriter.Write((IEnumerable<Collectors.OneDriveUsageRecord>)data),
            "reports.sharepoint" => csvWriter.Write((IEnumerable<Collectors.SharePointSiteUsageRecord>)data),
            "reports.teams" => csvWriter.Write((IEnumerable<Collectors.TeamsActivityRecord>)data),
            "reports.exchange" => csvWriter.Write((IEnumerable<Collectors.ExchangeMailboxUsageRecord>)data),
            
            // V2 Migration Risk Flags 🚩
            "entra.conditionalAccess" => csvWriter.Write((IEnumerable<Collectors.ConditionalAccessPolicyRecord>)data),
            "entra.crossTenantAccess" => csvWriter.Write((IEnumerable<Collectors.CrossTenantAccessRecord>)data),
            "entra.guests" => csvWriter.Write((IEnumerable<Collectors.GuestUserRecord>)data),
            "entra.groupInventoryPlus" => csvWriter.Write((IEnumerable<Collectors.GroupInventoryRecord>)data),
            "entra.appCredentials" => csvWriter.Write((IEnumerable<Collectors.AppCredentialRecord>)data),
            "entra.appAssignments" => csvWriter.Write((IEnumerable<Collectors.AppAssignmentRecord>)data),
            "entra.signInSignals" => csvWriter.Write((IEnumerable<Collectors.SignInSignalRecord>)data),
            "entra.authMethods" => csvWriter.Write((IEnumerable<Collectors.AuthMethodCoverageRecord>)data),
            "entra.directorySettings" => csvWriter.Write((IEnumerable<Collectors.DirectorySettingRecord>)data),
            "hybrid.aadConnectConfig" => csvWriter.Write((IEnumerable<Collectors.HybridAadConnectConfigRecord>)data),
            
            "organization.basic" => WriteOrganizationJson(filePath, (Collectors.OrganizationData)data),
            _ => throw new InvalidOperationException($"Unknown workload key: {workloadKey}")
        };

        if (workloadKey != "organization.basic")
        {
            await File.WriteAllTextAsync(filePath, csvContent, Encoding.UTF8, cancellationToken);
        }
    }

    private async Task WriteHeaderOnlyCsvAsync(string filePath, string workloadKey, CancellationToken cancellationToken)
    {
        var csvWriter = new CsvWriter();
        var csvContent = workloadKey switch
        {
            // V1
            "entra.users" => csvWriter.WriteHeaderOnly<Collectors.EntraUserRecord>(),
            "entra.groups" => csvWriter.WriteHeaderOnly<Collectors.EntraGroupRecord>(),
            "entra.m365groups" => csvWriter.WriteHeaderOnly<Collectors.M365GroupRecord>(),
            "entra.apps" => csvWriter.WriteHeaderOnly<Collectors.EntraApplicationRecord>(),
            "entra.applications" => csvWriter.WriteHeaderOnly<Collectors.EntraApplicationRecord>(),
            "entra.servicePrincipals" => csvWriter.WriteHeaderOnly<Collectors.EntraServicePrincipalRecord>(),
            "entra.roles" => csvWriter.WriteHeaderOnly<Collectors.EntraRoleRecord>(),
            "reports.onedrive" => csvWriter.WriteHeaderOnly<Collectors.OneDriveUsageRecord>(),
            "reports.sharepoint" => csvWriter.WriteHeaderOnly<Collectors.SharePointSiteUsageRecord>(),
            "reports.teams" => csvWriter.WriteHeaderOnly<Collectors.TeamsActivityRecord>(),
            "reports.exchange" => csvWriter.WriteHeaderOnly<Collectors.ExchangeMailboxUsageRecord>(),

            // V2 / current workload keys
            "entra.conditionalAccess" => csvWriter.WriteHeaderOnly<Collectors.ConditionalAccessPolicyRecord>(),
            "entra.crossTenantAccess" => csvWriter.WriteHeaderOnly<Collectors.CrossTenantAccessRecord>(),
            "entra.guests" => csvWriter.WriteHeaderOnly<Collectors.GuestUserRecord>(),
            "entra.groupInventoryPlus" => csvWriter.WriteHeaderOnly<Collectors.GroupInventoryRecord>(),
            "entra.appCredentials" => csvWriter.WriteHeaderOnly<Collectors.AppCredentialRecord>(),
            "entra.appAssignments" => csvWriter.WriteHeaderOnly<Collectors.AppAssignmentRecord>(),
            "entra.signInSignals" => csvWriter.WriteHeaderOnly<Collectors.SignInSignalRecord>(),
            "entra.authMethods" => csvWriter.WriteHeaderOnly<Collectors.AuthMethodCoverageRecord>(),
            "entra.directorySettings" => csvWriter.WriteHeaderOnly<Collectors.DirectorySettingRecord>(),
            "hybrid.aadConnectConfig" => csvWriter.WriteHeaderOnly<Collectors.HybridAadConnectConfigRecord>(),
            "m365.groups" => csvWriter.WriteHeaderOnly<Collectors.M365GroupRecord>(),
            "usage.onedrive" => csvWriter.WriteHeaderOnly<Collectors.OneDriveUsageRecord>(),
            "usage.sharepoint" => csvWriter.WriteHeaderOnly<Collectors.SharePointSiteUsageRecord>(),
            "usage.teams" => csvWriter.WriteHeaderOnly<Collectors.TeamsActivityRecord>(),
            "usage.exchange" => csvWriter.WriteHeaderOnly<Collectors.ExchangeMailboxUsageRecord>(),
            _ => string.Empty
        };

        if (!string.IsNullOrEmpty(csvContent))
        {
            await File.WriteAllTextAsync(filePath, csvContent, Encoding.UTF8, cancellationToken);
        }
    }

    private async Task WriteLegacyAliasCsvsAsync(string primaryFilePath, string workloadKey, CancellationToken cancellationToken)
    {
        var aliases = GetLegacyCsvAliases(workloadKey);
        if (aliases.Length == 0)
        {
            return;
        }

        foreach (var aliasName in aliases)
        {
            var aliasPath = Path.Combine(_context.OutputFolder, aliasName);
            if (string.Equals(aliasPath, primaryFilePath, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            // Keep alias byte-identical to primary file for downstream compatibility.
            var content = await File.ReadAllTextAsync(primaryFilePath, cancellationToken);
            await File.WriteAllTextAsync(aliasPath, content, Encoding.UTF8, cancellationToken);
        }
    }

    private static string[] GetLegacyCsvAliases(string workloadKey) => workloadKey switch
    {
        "entra.roles" => new[] { "Entra_Roles.csv" },
        _ => Array.Empty<string>()
    };

    private static bool IsCsvWorkload(string workloadKey) => workloadKey switch
    {
        "org.organization" => false,
        "organization.basic" => false,
        _ => true
    };

    private string WriteOrganizationJson(string basePath, Collectors.OrganizationData orgData)
    {
        // Write organization as JSON instead of CSV (complex structure)
        var jsonPath = basePath.Replace(".csv", ".json");
        var json = JsonSerializer.Serialize(orgData, new JsonSerializerOptions 
        { 
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        File.WriteAllText(jsonPath, json);
        return json; // Return for consistency, though not used
    }

    private async Task GenerateAccessGapsReportAsync(CancellationToken cancellationToken)
    {
        var gaps = new List<AccessGapRecord>();

        // From capability matrix
        foreach (var result in _results)
        {
            if (result.ConfidenceLevel == ConfidenceLevel.Unavailable || 
                result.ConfidenceLevel == ConfidenceLevel.Partial)
            {
                gaps.Add(new AccessGapRecord(
                    Capability: result.WorkloadKey,
                    Status: result.ConfidenceLevel.ToString(),
                    Message: result.Message,
                    RequiredScopes: GetRequiredScopes(result.WorkloadKey),
                    Impact: GetImpact(result.WorkloadKey)
                ));
            }
        }

        if (gaps.Any())
        {
            var filePath = Path.Combine(_context.OutputFolder, "Discovery_AccessGaps.csv");
            var csvWriter = new CsvWriter();
            var csv = csvWriter.Write(gaps);
            await File.WriteAllTextAsync(filePath, csv, Encoding.UTF8, cancellationToken);
            Console.WriteLine($"  ⚠ Access Gaps Report: Discovery_AccessGaps.csv ({gaps.Count} gaps)");
        }
    }

    private async Task GenerateSummaryAsync(CancellationToken cancellationToken)
    {
        var summaryRecords = _results.Select(r => new SummaryRecord(
            WorkloadKey: r.WorkloadKey,
            Success: r.Success,
            ItemCount: r.ItemCount,
            ConfidenceLevel: r.ConfidenceLevel.ToString(),
            Message: r.Message,
            ProcessedItems: r.Checkpoint.ItemsProcessed,
            Status: r.Checkpoint.Status.ToString()
        )).ToList();

        var filePath = Path.Combine(_context.OutputFolder, "Summary.csv");
        var csvWriter = new CsvWriter();
        var csv = csvWriter.Write(summaryRecords);
        await File.WriteAllTextAsync(filePath, csv, Encoding.UTF8, cancellationToken);
        Console.WriteLine($"  📊 Summary: Summary.csv ({summaryRecords.Count} collectors)");
    }

    private async Task GenerateMigrationRiskReportAsync(CancellationToken cancellationToken)
    {
        var riskReport = Analysis.MigrationRiskAnalyzer.AnalyzeRisks(_results);
        var filePath = Path.Combine(_context.OutputFolder, "RiskAnalysis.csv");
        var csvWriter = new CsvWriter();

        if (riskReport.Risks.Any())
        {
            var csv = csvWriter.Write(riskReport.Risks);
            await File.WriteAllTextAsync(filePath, csv, Encoding.UTF8, cancellationToken);

            var critical = riskReport.CriticalRisks;
            var high = riskReport.HighRisks;
            Console.WriteLine($"  🚨 Risk Analysis: RiskAnalysis.csv");
            Console.WriteLine($"     ├─ 🔴 Critical: {critical}");
            Console.WriteLine($"     ├─ 🟠 High: {high}");
            Console.WriteLine($"     ├─ 🟡 Medium: {riskReport.MediumRisks}");
            Console.WriteLine($"     └─ 🟢 Low: {riskReport.LowRisks}");
        }
        else
        {
            var csv = csvWriter.WriteHeaderOnly<Analysis.RiskItem>();
            await File.WriteAllTextAsync(filePath, csv, Encoding.UTF8, cancellationToken);
            Console.WriteLine($"  ✅ No migration risks detected");
            Console.WriteLine($"  📄 Risk Analysis: RiskAnalysis.csv (0 rows; header-only)");
        }
    }

    private async Task WriteMetadataAsync(CancellationToken cancellationToken)
    {
        var filePath = Path.Combine(_context.OutputFolder, "RunMetadata.json");
        var json = JsonSerializer.Serialize(_metadata, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        await File.WriteAllTextAsync(filePath, json, Encoding.UTF8, cancellationToken);
        Console.WriteLine($"  📄 Metadata: RunMetadata.json");
    }

    private void EnsureOutputDirectory()
    {
        if (!Directory.Exists(_context.OutputFolder))
        {
            Directory.CreateDirectory(_context.OutputFolder);
        }
    }

    private static string GetCsvFileName(string workloadKey) => workloadKey switch
    {
        // Entra ID
        "entra.users" => "Entra_Users.csv",
        "entra.groups" => "Entra_Groups.csv",
        "entra.applications" => "Entra_Applications.csv",
        "entra.servicePrincipals" => "Entra_ServicePrincipals.csv",
        "entra.roles" => "Entra_RoleAssignments.csv",
        
        // Entra ID - Access & Policy
        "entra.conditionalAccess" => "Entra_ConditionalAccessPolicies.csv",
        "entra.crossTenantAccess" => "Entra_CrossTenantAccess.csv",
        
        // Entra ID - User Analysis
        "entra.guests" => "Entra_GuestUsers.csv",
        "entra.signInSignals" => "Entra_SignInActivity.csv",
        "entra.authMethods" => "Entra_AuthMethodsCoverage.csv",
        
        // Entra ID - Group Analysis
        "entra.groupInventoryPlus" => "Entra_GroupInventory.csv",

        // Hybrid
        "hybrid.aadConnectConfig" => "Hybrid_AADConnectConfig.csv",
        
        // Entra ID - App Management
        "entra.appCredentials" => "Entra_AppCredentials.csv",
        "entra.appAssignments" => "Entra_AppAssignments.csv",
        
        // Entra ID - Directory Configuration
        "entra.directorySettings" => "Entra_DirectorySettings.csv",
        
        // Microsoft 365
        "m365.groups" => "M365_Groups.csv",
        "usage.onedrive" => "M365_OneDrive_Usage.csv",
        "usage.sharepoint" => "M365_SharePoint_Usage.csv",
        "usage.teams" => "M365_Teams_Usage.csv",
        "usage.exchange" => "M365_Exchange_Usage.csv",
        
        // Organization
        "org.organization" => "Organization.json",
        
        _ => $"{workloadKey.Replace(".", "_")}.csv"
    };

    private static string GetRequiredScopes(string workloadKey) => workloadKey switch
    {
        // V1
        "entra.users" => "User.Read.All or Directory.Read.All",
        "entra.groups" => "Group.Read.All or Directory.Read.All",
        "entra.m365groups" => "Group.Read.All or Directory.Read.All",
        "entra.apps" => "Application.Read.All or Directory.Read.All",
        "entra.servicePrincipals" => "Application.Read.All or Directory.Read.All",
        "entra.roles" => "RoleManagement.Read.All or Directory.Read.All",
        "reports.onedrive" => "Reports.Read.All",
        "reports.sharepoint" => "Reports.Read.All",
        "reports.teams" => "Reports.Read.All",
        "reports.exchange" => "Reports.Read.All",
        "organization.basic" => "Organization.Read.All or Directory.Read.All",
        
        // V2 Migration Risk Flags
        "entra.conditionalAccess" => "Policy.Read.All",
        "entra.crossTenantAccess" => "Policy.Read.All, Directory.Read.All",
        "entra.guests" => "User.Read.All, Group.Read.All",
        "entra.groupInventoryPlus" => "Group.Read.All",
        "entra.appCredentials" => "Application.Read.All",
        "entra.appAssignments" => "Application.Read.All, Directory.Read.All",
        "entra.signInSignals" => "AuditLog.Read.All, User.Read.All",
        "entra.authMethods" => "Reports.Read.All, User.Read.All",
        "entra.directorySettings" => "Directory.Read.All",
        "hybrid.aadConnectConfig" => "OnPremDirectorySynchronization.Read.All, Organization.Read.All (or Directory.Read.All)",
        
        _ => "Unknown"
    };

    private static string GetImpact(string workloadKey) => workloadKey switch
    {
        // V1
        "entra.users" => "Cannot collect user inventory and license assignments",
        "entra.groups" => "Cannot collect security and distribution groups",
        "entra.m365groups" => "Cannot collect M365 Groups and Teams data",
        "entra.apps" => "Cannot collect application registrations",
        "entra.servicePrincipals" => "Cannot collect enterprise applications",
        "entra.roles" => "Cannot collect directory role assignments",
        "reports.onedrive" => "Cannot collect OneDrive usage metrics",
        "reports.sharepoint" => "Cannot collect SharePoint site usage",
        "reports.teams" => "Cannot collect Teams activity data",
        "reports.exchange" => "Cannot collect Exchange mailbox usage",
        "organization.basic" => "Cannot collect organization settings and domains",
        
        // V2 Migration Risk Flags
        "entra.conditionalAccess" => "🚨 Critical: Cannot assess CA policy migration risks (sign-in breakage likely)",
        "entra.crossTenantAccess" => "⚠️ Cannot assess B2B collaboration and guest access dependencies",
        "entra.guests" => "⚠️ Cannot identify guest users and collaboration risks",
        "entra.groupInventoryPlus" => "⚠️ Cannot detect orphaned groups or governance issues",
        "entra.appCredentials" => "🚨 Critical: Cannot identify expiring app credentials during migration",
        "entra.appAssignments" => "⚠️ Cannot assess high-privilege app dependencies",
        "entra.signInSignals" => "Cannot identify inactive users or legacy auth usage",
        "entra.authMethods" => "Cannot assess MFA/SSPR/passwordless registration coverage",
        "entra.directorySettings" => "Cannot assess behavior-changing directory configurations",
        "hybrid.aadConnectConfig" => "Cannot assess Entra Connect sync posture and hybrid identity configuration",
        
        _ => "Unknown impact"
    };
}

public sealed class RunMetadata
{
    public string RunName { get; set; }
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }
    public string TenantId { get; set; }
    public string Username { get; set; }
    public string[] GrantedScopes { get; set; }
    public Dictionary<string, string> CapabilityMatrix { get; set; }
    public int TotalCollectors { get; set; }
    public int SuccessfulCollectors { get; set; }
    public int FailedCollectors { get; set; }
    public int TotalItemsCollected { get; set; }
    public List<string> Errors { get; set; } = new();

    public RunMetadata(
        string runName,
        DateTimeOffset startedAt,
        string tenantId,
        string username,
        string[] grantedScopes,
        Dictionary<string, string> capabilityMatrix)
    {
        RunName = runName;
        StartedAt = startedAt;
        TenantId = tenantId;
        Username = username;
        GrantedScopes = grantedScopes;
        CapabilityMatrix = capabilityMatrix;
    }
}

public sealed record AccessGapRecord(
    string Capability,
    string Status,
    string Message,
    string RequiredScopes,
    string Impact
);

public sealed record SummaryRecord(
    string WorkloadKey,
    bool Success,
    int ItemCount,
    string ConfidenceLevel,
    string Message,
    int ProcessedItems,
    string Status
);
