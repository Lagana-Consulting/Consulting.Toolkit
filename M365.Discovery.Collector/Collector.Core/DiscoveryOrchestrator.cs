using Collector.Core.Collectors;
using Collector.Core.Output;
using Collector.Graph;
using Collector.Graph.Auth;

namespace Collector.Core;

public sealed class DiscoveryOrchestrator
{
    public async Task<DiscoveryResult> RunAsync(
        AuthConfig authConfig,
        DiscoveryContext context,
        IProgress<string>? progress = null,
        CancellationToken cancellationToken = default)
    {
        Console.WriteLine($"\n🚀 Starting discovery run: {context.RunName}");
        Console.WriteLine($"📂 Output folder: {context.OutputFolder}");
        Console.WriteLine();

        // Step 1: Authenticate and create Graph client
        var factory = new GraphClientFactory(authConfig);
        var (graphClient, tokenInfo) = await factory.CreateAuthenticatedClientAsync();
        var resilientClient = new ResilientGraphClient(graphClient, maxParallelRequests: 4);

        Console.WriteLine($"🔍 Token expires: {tokenInfo.ExpiresOn:yyyy-MM-dd HH:mm:ss} UTC");
        if (!string.IsNullOrWhiteSpace(tokenInfo.AuthenticationPath))
        {
            Console.WriteLine($"🔐 Auth path: {tokenInfo.AuthenticationPath}");
        }
        Console.WriteLine();

        // Step 2: Run preflight checks
        Console.WriteLine("🔎 Running preflight checks...");
        var preflightService = new PreflightService(resilientClient);
        var preflightReport = await preflightService.RunPreflightAsync(tokenInfo, cancellationToken);

        Console.WriteLine($"   {preflightReport.OrganizationTestMessage}");
        Console.WriteLine($"   Granted permissions: {tokenInfo.GrantedScopes.Length}");
        Console.WriteLine();

        // Display capability matrix
        DisplayCapabilityMatrix(preflightReport.CapabilityMatrix);

        // Step 3: Initialize output manager
        var outputManager = new OutputManager(context, preflightReport);

        // Step 4: Run collectors
        var collectors = new List<(string Name, IWorkloadCollector Collector)>
        {
            // === V2 - MIGRATION RISK FLAGS (Priority #1) ===
            ("🚩 Conditional Access Policies", new ConditionalAccessCollector(resilientClient)),
            ("🚩 Cross-Tenant Access Settings", new CrossTenantAccessCollector(resilientClient)),
            ("🚩 Guest Users", new GuestUsersCollector(resilientClient)),
            ("🚩 Group Inventory (Owners & Counts)", new GroupInventoryPlusCollector(resilientClient)),
            ("🚩 App Credentials Expiration", new AppCredentialsCollector(resilientClient)),
            ("🚩 App Role Assignments", new AppAssignmentsCollector(resilientClient)),
            ("🚩 Sign-In Activity Signals", new SignInSignalsCollector(resilientClient)),
            ("🚩 Directory Settings", new DirectorySettingsCollector(resilientClient)),
            
            // === V1 - Core Entra Directory ===
            ("Entra Users", new EntraUsersCollector(resilientClient)),
            ("Entra Groups", new EntraGroupsCollector(resilientClient)),
            ("M365 Groups", new M365GroupsCollector(resilientClient)),
            ("Entra Applications", new EntraApplicationsCollector(resilientClient)),
            ("Entra Service Principals", new EntraServicePrincipalsCollector(resilientClient)),
            ("Entra Roles", new EntraRolesCollector(resilientClient)),
            
            // === V1 - Organization ===
            ("Organization", new OrganizationCollector(resilientClient)),
            
            // === V1 - Usage Reports ===
            ("OneDrive Usage", new OneDriveUsageCollector(resilientClient)),
            ("SharePoint Usage", new SharePointUsageCollector(resilientClient)),
            ("Teams Activity", new TeamsActivityCollector(resilientClient)),
            ("Exchange Mailbox Usage", new ExchangeMailboxUsageCollector(resilientClient)),
        };

        Console.WriteLine($"📊 Running {collectors.Count} collectors (8 migration risk flags + {collectors.Count - 8} baseline)...\n");

        foreach (var (name, collector) in collectors)
        {
            Console.WriteLine($"▶ {name}");
            
            var result = await collector.CollectAsync(context, progress, cancellationToken);
            outputManager.AddResult(result);

            var statusIcon = result.Success ? "✅" : "❌";
            var confidenceIcon = result.ConfidenceLevel switch
            {
                ConfidenceLevel.Authoritative => "🟢",
                ConfidenceLevel.Partial => "🟡",
                ConfidenceLevel.Unavailable => "🔴",
                _ => "⚪"
            };
            
            Console.WriteLine($"  {statusIcon} {confidenceIcon} {result.Message}");
            Console.WriteLine();
        }

        // Step 5: Finalize outputs
        Console.WriteLine($"📝 Generating output files...");
        await outputManager.FinalizeAsync(cancellationToken);

        return new DiscoveryResult(true, "Discovery completed successfully");
    }

    private static void DisplayCapabilityMatrix(CapabilityMatrix matrix)
    {
        Console.WriteLine("📊 Capability Matrix:");
        Console.WriteLine("   ┌─────────────────────────────────┬──────────┐");
        Console.WriteLine("   │ Capability                      │ Status   │");
        Console.WriteLine("   ├─────────────────────────────────┼──────────┤");

        foreach (var (key, status) in matrix.Capabilities.OrderBy(k => k.Key))
        {
            var icon = status switch
            {
                CapabilityStatus.Available => "✅",
                CapabilityStatus.Partial => "⚠",
                CapabilityStatus.Blocked => "❌",
                _ => "?"
            };

            var displayName = key.PadRight(31);
            var statusText = status.ToString().PadRight(8);
            Console.WriteLine($"   │ {displayName} │ {icon} {statusText} │");
        }

        Console.WriteLine("   └─────────────────────────────────┴──────────┘");
        Console.WriteLine();
    }
}

public sealed record DiscoveryResult(bool Success, string Message);
