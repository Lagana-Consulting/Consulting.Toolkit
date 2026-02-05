using Collector.Core;

namespace Collector.ConsoleApp;

class Program
{
    static async Task<int> Main(string[] args)
    {
        try
        {
            Console.WriteLine("╔════════════════════════════════════════════════════════╗");
            Console.WriteLine("║       M365 Discovery Collector v1.0                    ║");
            Console.WriteLine("╚════════════════════════════════════════════════════════╝");
            Console.WriteLine();

            // Step 1: Get authentication configuration
            var authConfig = ConfigurationPrompt.LoadOrPromptConfig(configFilePath: "collector-config.json");
            ConfigurationPrompt.DisplayConfigSummary(authConfig);

            // Step 2: Set up discovery context
            var runName = $"Discovery_{DateTime.UtcNow:yyyyMMdd_HHmmss}";
            var outputFolder = Path.Combine(Environment.CurrentDirectory, "CollectorOutput", runName);
            var context = new DiscoveryContext(outputFolder, runName);

            // Step 3: Run discovery
            var orchestrator = new DiscoveryOrchestrator();
            var result = await orchestrator.RunAsync(authConfig, context, cancellationToken: default);

            if (result.Success)
            {
                Console.WriteLine("\n✅ Discovery completed successfully!");
                return 0;
            }
            else
            {
                Console.WriteLine($"\n❌ Discovery failed: {result.Message}");
                return 1;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"\n💥 Fatal error: {ex.Message}");
            Console.WriteLine(ex.StackTrace);
            return 1;
        }
    }
}