// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using System.Text.Json;
using Collector.Core;
using Collector.Core.Collectors;
using Collector.Core.Output;
using Collector.Graph;
using Collector.Graph.Auth;

namespace Collector.ConsoleApp;

internal static class Program
{
    private enum ExecutionRole
    {
        Operator,
        BootstrapAdmin
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static async Task<int> Main(string[] args)
    {
        try
        {
            var parsed = ParseArgs(args);
            if (parsed.HasFlag("help") || parsed.HasFlag("h") || parsed.HasFlag("?"))
            {
                PrintHelp();
                return 0;
            }

            if (!parsed.HasFlag("no-banner"))
            {
                PrintBanner();
            }

            var role = ResolveExecutionRole(parsed);
            var catalog = WorkloadCatalog.CreateDefault();
            if (parsed.HasFlag("list-workloads"))
            {
                PrintWorkloads(catalog);
                return 0;
            }

            if (parsed.HasFlag("self-check"))
            {
                return RunSelfCheck(parsed, catalog, role);
            }

            if (role == ExecutionRole.BootstrapAdmin)
            {
                throw new InvalidOperationException(
                    "Role boundary enforced: this CLI run path is operator-only (preflight/discovery). " +
                    "Use --role operator for run/preflight, and use the app setup flow for bootstrap actions.");
            }

            var authConfig = ResolveAuthConfig(parsed);
            var selectedWorkloads = ResolveWorkloads(parsed, catalog);

            var outputRoot = parsed.GetValue("output-root") ??
                             Path.Combine(Environment.CurrentDirectory, "CollectorOutput");
            var runName = parsed.GetValue("run-name") ??
                          $"Discovery_{DateTime.UtcNow:yyyyMMdd_HHmmss}";
            var outputFolder = Path.Combine(outputRoot, runName);
            Directory.CreateDirectory(outputFolder);

            Console.WriteLine($"Run Name: {runName}");
            Console.WriteLine($"Output:   {outputFolder}");
            Console.WriteLine($"Role:     {role}");
            Console.WriteLine($"Mode:     {authConfig.Mode}");
            Console.WriteLine($"Workloads ({selectedWorkloads.Count}): {string.Join(", ", selectedWorkloads)}");
            Console.WriteLine();

            var factory = new GraphClientFactory(authConfig);
            var (graphClient, tokenInfo) = await factory.CreateAuthenticatedClientAsync();
            var resilientClient = new ResilientGraphClient(graphClient, maxParallelRequests: 4);
            var preflightService = new PreflightService(resilientClient);

            Console.WriteLine("Preflight check started.");
            var preflightReport = await preflightService.RunPreflightAsync(tokenInfo);
            Console.WriteLine($"  {preflightReport.OrganizationTestMessage}");

            foreach (var key in selectedWorkloads)
            {
                var workload = catalog.Workloads.FirstOrDefault(w => w.Key == key);
                var display = workload?.DisplayName ?? key;
                var check = await preflightService.CheckAsync(new DiscoveryContext(outputFolder, runName), key);
                Console.WriteLine($"  {display}: {check.Message}");
            }
            Console.WriteLine("Preflight completed.");
            Console.WriteLine();

            if (parsed.HasFlag("preflight-only"))
            {
                return 0;
            }

            var outputManager = new OutputManager(new DiscoveryContext(outputFolder, runName), preflightReport);
            var collectorMap = BuildCollectorMap(resilientClient);

            Console.WriteLine($"Collecting {selectedWorkloads.Count} workload(s)...");
            foreach (var key in selectedWorkloads)
            {
                if (!collectorMap.TryGetValue(key, out var collector))
                {
                    Console.WriteLine($"  ⚠ No collector registered for key: {key}");
                    continue;
                }

                var workload = catalog.Workloads.FirstOrDefault(w => w.Key == key);
                var display = workload?.DisplayName ?? key;
                Console.WriteLine($"▶ {display}...");
                var progress = new Progress<string>(m => Console.WriteLine($"  {m}"));
                var result = await collector.CollectAsync(new DiscoveryContext(outputFolder, runName), progress, default);
                outputManager.AddResult(result);
                Console.WriteLine($"  {(result.Success ? "✅" : "❌")} {result.Message}");
                Console.WriteLine();
            }

            Console.WriteLine("Generating output files...");
            await outputManager.FinalizeAsync(default);
            Console.WriteLine("Discovery complete.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Fatal error: {ex.Message}");
            return 1;
        }
    }

    private static Dictionary<string, IWorkloadCollector> BuildCollectorMap(ResilientGraphClient client)
    {
        return new Dictionary<string, IWorkloadCollector>(StringComparer.OrdinalIgnoreCase)
        {
            { "entra.conditionalAccess", new ConditionalAccessCollector(client) },
            { "entra.crossTenantAccess", new CrossTenantAccessCollector(client) },
            { "entra.guests", new GuestUsersCollector(client) },
            { "entra.groupInventoryPlus", new GroupInventoryPlusCollector(client) },
            { "entra.appCredentials", new AppCredentialsCollector(client) },
            { "entra.appAssignments", new AppAssignmentsCollector(client) },
            { "entra.signInSignals", new SignInSignalsCollector(client) },
            { "entra.authMethods", new AuthMethodsCoverageCollector(client) },
            { "entra.directorySettings", new DirectorySettingsCollector(client) },
            { "hybrid.aadConnectConfig", new HybridAadConnectConfigCollector(client) },
            { "entra.users", new EntraUsersCollector(client) },
            { "entra.groups", new EntraGroupsCollector(client) },
            { "entra.applications", new EntraApplicationsCollector(client) },
            { "entra.servicePrincipals", new EntraServicePrincipalsCollector(client) },
            { "entra.roles", new EntraRolesCollector(client) },
            { "org.organization", new OrganizationCollector(client) },
            { "usage.onedrive", new OneDriveUsageCollector(client) },
            { "usage.sharepoint", new SharePointUsageCollector(client) },
            { "usage.teams", new TeamsActivityCollector(client) },
            { "usage.exchange", new ExchangeMailboxUsageCollector(client) },
            { "m365.groups", new M365GroupsCollector(client) }
        };
    }

    private static List<string> ResolveWorkloads(ArgSet args, WorkloadCatalog catalog)
    {
        var requested = args.GetValue("workloads");
        if (string.IsNullOrWhiteSpace(requested) || requested.Equals("default", StringComparison.OrdinalIgnoreCase))
        {
            return catalog.Workloads
                .Where(w => w.IsDefaultSelected)
                .Select(w => w.Key)
                .ToList();
        }

        if (requested.Equals("all", StringComparison.OrdinalIgnoreCase))
        {
            return catalog.Workloads.Select(w => w.Key).ToList();
        }

        var keys = requested
            .Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(k => k.Trim())
            .Where(k => !string.IsNullOrWhiteSpace(k))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        var valid = catalog.Workloads.Select(w => w.Key).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var unknown = keys.Where(k => !valid.Contains(k)).ToList();
        if (unknown.Count > 0)
        {
            throw new InvalidOperationException($"Unknown workload key(s): {string.Join(", ", unknown)}");
        }

        return keys;
    }

    private static AuthConfig ResolveAuthConfig(ArgSet args)
    {
        var hasDirectArgs = args.HasValue("mode") || args.HasValue("client-id") || args.HasValue("tenant-id") ||
                            args.HasValue("cert-thumbprint") || args.HasValue("cert-subject") ||
                            args.HasValue("client-secret");

        if (!hasDirectArgs)
        {
            var configWasExplicit = args.HasValue("config");
            var configPath = args.GetValue("config") ?? "collector-config.json";
            if (!File.Exists(configPath))
            {
                var guiConfigPath = GetGuiDefaultConfigPath();
                var isDefaultConfigName = configPath.Equals("collector-config.json", StringComparison.OrdinalIgnoreCase);
                var shouldTryGuiFallback = !configWasExplicit || isDefaultConfigName;

                if (shouldTryGuiFallback && File.Exists(guiConfigPath))
                {
                    Console.WriteLine($"Config fallback: using GUI config at {guiConfigPath}");
                    return LoadAuthConfig(guiConfigPath);
                }

                throw new InvalidOperationException(
                    $"No direct auth args provided and config file not found: {configPath}");
            }

            return LoadAuthConfig(configPath);
        }

        var modeRaw = args.GetValue("mode");
        if (string.IsNullOrWhiteSpace(modeRaw))
        {
            throw new InvalidOperationException("--mode is required when using direct auth args.");
        }

        var clientId = args.GetValue("client-id");
        if (string.IsNullOrWhiteSpace(clientId))
        {
            throw new InvalidOperationException("--client-id is required.");
        }

        if (modeRaw.Equals("delegated", StringComparison.OrdinalIgnoreCase))
        {
            var tenant = args.GetValue("tenant-id");
            return AuthConfig.CreateDelegated(clientId, tenant);
        }

        if (!modeRaw.Equals("app-only", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Invalid --mode. Use 'delegated' or 'app-only'.");
        }

        var appTenant = args.GetValue("tenant-id");
        if (string.IsNullOrWhiteSpace(appTenant))
        {
            throw new InvalidOperationException("--tenant-id is required for app-only mode.");
        }

        var thumbprint = args.GetValue("cert-thumbprint");
        var subject = args.GetValue("cert-subject");
        var secret = args.GetValue("client-secret");

        if (!string.IsNullOrWhiteSpace(thumbprint))
        {
            return AuthConfig.CreateAppOnlyWithCertificateByThumbprint(clientId, appTenant, thumbprint);
        }

        if (!string.IsNullOrWhiteSpace(subject))
        {
            return AuthConfig.CreateAppOnlyWithCertificateBySubject(clientId, appTenant, subject);
        }

        if (!string.IsNullOrWhiteSpace(secret))
        {
            return AuthConfig.CreateAppOnly(clientId, appTenant, secret);
        }

        throw new InvalidOperationException(
            "App-only mode requires one of: --cert-thumbprint, --cert-subject, or --client-secret.");
    }

    private static AuthConfig LoadAuthConfig(string path)
    {
        var raw = File.ReadAllText(path);

        // Try native AuthConfig JSON first.
        AuthConfig? direct = null;
        try
        {
            direct = JsonSerializer.Deserialize<AuthConfig>(raw, JsonOptions);
        }
        catch (JsonException)
        {
            // Not in native AuthConfig shape; continue with GUI config fallback parsing below.
        }

        if (direct != null && !string.IsNullOrWhiteSpace(direct.ClientId))
        {
            direct.Validate();
            return direct;
        }

        // Fallback for GUI config format.
        using var doc = JsonDocument.Parse(raw);
        var root = doc.RootElement;
        var clientId = TryGetString(root, "ClientId");
        var tenantId = TryGetString(root, "TenantId");
        var useAppOnly = TryGetBool(root, "UseAppOnlyCertificateSignIn");
        var thumb = TryGetString(root, "CertificateThumbprint");
        var subject = TryGetString(root, "CertificateSubjectName");

        if (string.IsNullOrWhiteSpace(clientId))
        {
            throw new InvalidOperationException($"Config missing ClientId: {path}");
        }

        if (useAppOnly)
        {
            if (string.IsNullOrWhiteSpace(tenantId))
            {
                throw new InvalidOperationException($"Config missing TenantId for app-only mode: {path}");
            }

            if (!string.IsNullOrWhiteSpace(thumb))
            {
                return AuthConfig.CreateAppOnlyWithCertificateByThumbprint(clientId, tenantId, thumb);
            }

            if (!string.IsNullOrWhiteSpace(subject))
            {
                return AuthConfig.CreateAppOnlyWithCertificateBySubject(clientId, tenantId, subject);
            }

            throw new InvalidOperationException(
                $"App-only config requires CertificateThumbprint or CertificateSubjectName: {path}");
        }

        return AuthConfig.CreateDelegated(clientId, tenantId);
    }

    private static string? TryGetString(JsonElement root, string name)
    {
        return root.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String
            ? p.GetString()
            : null;
    }

    private static bool TryGetBool(JsonElement root, string name)
    {
        return root.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.True
            ? true
            : false;
    }

    private static void PrintBanner()
    {
        Console.WriteLine("M365 Discovery Collector CLI");
        Console.WriteLine("----------------------------");
    }

    private static void PrintWorkloads(WorkloadCatalog catalog)
    {
        Console.WriteLine("Available workloads:");
        foreach (var w in catalog.Workloads.OrderBy(w => w.Category).ThenBy(w => w.Key))
        {
            var defaultTag = w.IsDefaultSelected ? " (default)" : string.Empty;
            Console.WriteLine($"- {w.Key}{defaultTag}");
            Console.WriteLine($"  {w.DisplayName} [{w.Category}]");
        }
    }

    private static void PrintHelp()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  Collector.Console [options]");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --help, -h                      Show help");
        Console.WriteLine("  --role <operator|bootstrap-admin> Execution role (default: operator)");
        Console.WriteLine("  --list-workloads                Print workload keys and exit");
        Console.WriteLine("  --self-check                    Validate config/role/workloads/output access and exit");
        Console.WriteLine("  --preflight-only                Run auth + preflight only");
        Console.WriteLine("  --workloads <list|all|default>  Comma list of workload keys (default: default)");
        Console.WriteLine("  --output-root <path>            Root output folder (default: ./CollectorOutput)");
        Console.WriteLine("  --run-name <name>               Run name (default: Discovery_yyyyMMdd_HHmmss)");
        Console.WriteLine("  --config <path>                 Auth config file (default: collector-config.json)");
        Console.WriteLine("                                   Fallback when missing: %APPDATA%/M365DiscoveryCollector/config.json");
        Console.WriteLine("  --mode <delegated|app-only>     Direct auth mode (overrides config)");
        Console.WriteLine("  --client-id <guid>              App registration client ID");
        Console.WriteLine("  --tenant-id <id/domain>         Tenant ID/domain (required for app-only)");
        Console.WriteLine("  --cert-thumbprint <thumb>       App-only certificate thumbprint");
        Console.WriteLine("  --cert-subject <subject>        App-only certificate subject");
        Console.WriteLine("  --client-secret <secret>        App-only secret fallback");
        Console.WriteLine("  --no-banner                     Suppress banner");
    }

    private static int RunSelfCheck(ArgSet args, WorkloadCatalog catalog, ExecutionRole role)
    {
        var failures = 0;

        Console.WriteLine("Self-check started.");

        if (role == ExecutionRole.Operator)
        {
            Console.WriteLine("  ✅ Role boundary: operator role accepted for runtime preflight/discovery.");
        }
        else
        {
            failures++;
            Console.WriteLine("  ❌ Role boundary: bootstrap-admin is not permitted for runtime CLI run path.");
            Console.WriteLine("     Use --role operator for preflight/discovery execution.");
        }

        try
        {
            var selectedWorkloads = ResolveWorkloads(args, catalog);
            Console.WriteLine($"  ✅ Workload selection: {selectedWorkloads.Count} workload(s) resolved.");
        }
        catch (Exception ex)
        {
            failures++;
            Console.WriteLine($"  ❌ Workload selection: {ex.Message}");
        }

        AuthConfig? authConfig = null;
        try
        {
            authConfig = ResolveAuthConfig(args);
            authConfig.Validate();
            Console.WriteLine($"  ✅ Auth config: resolved and valid (mode: {authConfig.Mode}).");

            if (authConfig.Mode == AuthMode.AppOnly &&
                authConfig.TenantId?.Equals("organizations", StringComparison.OrdinalIgnoreCase) == true)
            {
                failures++;
                Console.WriteLine("  ❌ Auth prerequisite: app-only mode requires a specific tenant ID/domain, not 'organizations'.");
            }
        }
        catch (Exception ex)
        {
            failures++;
            Console.WriteLine($"  ❌ Auth config: {ex.Message}");
        }

        var outputRoot = args.GetValue("output-root") ??
                         Path.Combine(Environment.CurrentDirectory, "CollectorOutput");
        try
        {
            Directory.CreateDirectory(outputRoot);
            var probePath = Path.Combine(outputRoot, $".selfcheck-write-{Guid.NewGuid():N}.tmp");
            File.WriteAllText(probePath, "ok");
            File.Delete(probePath);
            Console.WriteLine($"  ✅ Output access: writable ({outputRoot}).");
        }
        catch (Exception ex)
        {
            failures++;
            Console.WriteLine($"  ❌ Output access: cannot write to '{outputRoot}'. {ex.Message}");
        }

        if (failures == 0)
        {
            Console.WriteLine("Self-check completed: PASS.");
            return 0;
        }

        Console.WriteLine($"Self-check completed: FAIL ({failures} issue(s)).");
        return 1;
    }

    private static string GetGuiDefaultConfigPath()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "M365DiscoveryCollector", "config.json");
    }

    private static ExecutionRole ResolveExecutionRole(ArgSet args)
    {
        var roleRaw = args.GetValue("role");
        if (string.IsNullOrWhiteSpace(roleRaw))
        {
            return ExecutionRole.Operator;
        }

        if (roleRaw.Equals("operator", StringComparison.OrdinalIgnoreCase))
        {
            return ExecutionRole.Operator;
        }

        if (roleRaw.Equals("bootstrap-admin", StringComparison.OrdinalIgnoreCase))
        {
            return ExecutionRole.BootstrapAdmin;
        }

        throw new InvalidOperationException("Invalid --role. Use 'operator' or 'bootstrap-admin'.");
    }

    private static ArgSet ParseArgs(string[] args)
    {
        var parsed = new ArgSet();
        for (var i = 0; i < args.Length; i++)
        {
            var token = args[i];
            if (!token.StartsWith("-"))
            {
                continue;
            }

            var key = token.TrimStart('-');
            if (string.IsNullOrWhiteSpace(key))
            {
                continue;
            }

            if (i + 1 < args.Length && !args[i + 1].StartsWith("-"))
            {
                parsed.Values[key] = args[i + 1];
                i++;
            }
            else
            {
                parsed.Flags.Add(key);
            }
        }
        return parsed;
    }

    private sealed class ArgSet
    {
        public Dictionary<string, string> Values { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> Flags { get; } = new(StringComparer.OrdinalIgnoreCase);

        public bool HasFlag(string name) => Flags.Contains(name);
        public bool HasValue(string name) => Values.ContainsKey(name);
        public string? GetValue(string name) => Values.TryGetValue(name, out var v) ? v : null;
    }
}
