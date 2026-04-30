// Copyright (c) 2024 Lagana Consulting. All rights reserved.
// Proprietary and confidential. Unauthorized copying or distribution is prohibited.
using System.Text.Json;
using Collector.Graph; // Add this

namespace Collector.Core;

public static class ConfigurationPrompt
{
    /// <summary>
    /// Prompt user for authentication configuration at runtime
    /// </summary>
    public static AuthConfig PromptForAuthConfig()
    {
        Console.WriteLine("╔════════════════════════════════════════════════════════╗");
        Console.WriteLine("║  M365 Discovery Collector - Authentication Setup      ║");
        Console.WriteLine("╚════════════════════════════════════════════════════════╝");
        Console.WriteLine();

        // Step 1: Choose auth mode
        Console.WriteLine("Select authentication mode:");
        Console.WriteLine("  1. Interactive (Delegated) - Sign in as a user");
        Console.WriteLine("  2. App-Only (Service Principal) - Unattended with client secret");
        Console.Write("\nEnter choice [1-2]: ");
        
        var modeChoice = Console.ReadLine()?.Trim();
        var mode = modeChoice == "2" ? AuthMode.AppOnly : AuthMode.InteractiveDelegated;

        Console.WriteLine();
        
        // Step 2: Collect common parameters
        Console.WriteLine("Enter your Azure AD app registration details:");
        Console.WriteLine("(You must create an app registration in Azure Portal first)");
        Console.WriteLine();

        Console.Write("Client ID (Application ID): ");
        var clientId = Console.ReadLine()?.Trim();
        if (string.IsNullOrWhiteSpace(clientId))
        {
            throw new InvalidOperationException("Client ID is required");
        }

        Console.Write("Tenant ID (or domain name): ");
        var tenantId = Console.ReadLine()?.Trim();
        if (string.IsNullOrWhiteSpace(tenantId))
        {
            throw new InvalidOperationException("Tenant ID is required");
        }

        Console.WriteLine();

        // Step 3: Mode-specific configuration
        if (mode == AuthMode.AppOnly)
        {
            Console.WriteLine("Select app-only credential method:");
            Console.WriteLine("  1. Certificate (thumbprint) - recommended");
            Console.WriteLine("  2. Certificate (subject name)");
            Console.WriteLine("  3. Client secret fallback (lab only)");
            Console.Write("\nEnter choice [1-3]: ");
            var credentialChoice = Console.ReadLine()?.Trim();
            Console.WriteLine();

            if (credentialChoice == "2")
            {
                Console.Write("Certificate Subject Name: ");
                var subjectName = Console.ReadLine()?.Trim();
                if (string.IsNullOrWhiteSpace(subjectName))
                {
                    throw new InvalidOperationException("Certificate subject name is required.");
                }

                Console.WriteLine();
                Console.WriteLine("✅ App-only authentication configured (certificate subject)");
                return AuthConfig.CreateAppOnlyWithCertificateBySubject(clientId, tenantId, subjectName);
            }

            if (credentialChoice == "3")
            {
                Console.WriteLine("⚠ WARNING: Client secret will be visible as you type");
                Console.Write("Client Secret: ");
                var clientSecret = ReadSecret();
                Console.WriteLine();

                if (string.IsNullOrWhiteSpace(clientSecret))
                {
                    throw new InvalidOperationException("Client secret is required for fallback mode.");
                }

                Console.WriteLine();
                Console.WriteLine("✅ App-only authentication configured (client secret fallback)");
                return AuthConfig.CreateAppOnly(clientId, tenantId, clientSecret);
            }

            Console.Write("Certificate Thumbprint: ");
            var thumbprint = Console.ReadLine()?.Trim();
            if (string.IsNullOrWhiteSpace(thumbprint))
            {
                throw new InvalidOperationException("Certificate thumbprint is required.");
            }

            Console.WriteLine();
            Console.WriteLine("✅ App-only authentication configured (certificate thumbprint)");
            return AuthConfig.CreateAppOnlyWithCertificateByThumbprint(clientId, tenantId, thumbprint);
        }
        else
        {
            Console.WriteLine("✅ Interactive authentication configured");
            Console.WriteLine("   You will be prompted to sign in when the collection starts.");
            Console.WriteLine();
            
            return AuthConfig.CreateDelegated(clientId, tenantId);
        }
    }

    /// <summary>
    /// Load configuration from file if exists, otherwise prompt
    /// </summary>
    public static AuthConfig LoadOrPromptConfig(string? configFilePath = null)
    {
        // Try to load from file first
        if (!string.IsNullOrWhiteSpace(configFilePath) && File.Exists(configFilePath))
        {
            try
            {
                var json = File.ReadAllText(configFilePath);
                var config = JsonSerializer.Deserialize<AuthConfig>(json, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });

                if (config != null)
                {
                    Console.WriteLine($"✅ Loaded configuration from: {configFilePath}");
                    return config;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"⚠ Failed to load config file: {ex.Message}");
                Console.WriteLine("Falling back to interactive prompt...\n");
            }
        }

        // Fall back to prompt
        return PromptForAuthConfig();
    }

    /// <summary>
    /// Save configuration to file (WARNING: includes secrets!)
    /// </summary>
    public static void SaveConfig(AuthConfig config, string filePath)
    {
        var json = JsonSerializer.Serialize(config, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        File.WriteAllText(filePath, json);
        
        Console.WriteLine($"\n⚠ WARNING: Configuration saved to {filePath}");
        Console.WriteLine("   This file contains secrets! Add to .gitignore and restrict permissions.");
    }

    private static string ReadSecret()
    {
        // Note: For better security, could implement masked input
        // For now, standard ReadLine (visible text)
        return Console.ReadLine()?.Trim() ?? string.Empty;
    }

    /// <summary>
    /// Display configuration summary (without secrets)
    /// </summary>
    public static void DisplayConfigSummary(AuthConfig config)
    {
        Console.WriteLine("\n📋 Configuration Summary:");
        Console.WriteLine($"   Auth Mode: {config.Mode}");
        Console.WriteLine($"   Client ID: {config.ClientId}");
        Console.WriteLine($"   Tenant ID: {config.TenantId}");
        
        if (config.Mode == AuthMode.AppOnly)
        {
            var certDisplay = !string.IsNullOrWhiteSpace(config.CertificateThumbprint)
                ? $"thumbprint:{config.CertificateThumbprint}"
                : (!string.IsNullOrWhiteSpace(config.CertificateSubjectName) ? $"subject:{config.CertificateSubjectName}" : "(not set)");
            var secretMasked = config.ClientSecret?.Length > 0
                ? new string('*', Math.Min(config.ClientSecret.Length, 20))
                : "(not set)";

            Console.WriteLine($"   Certificate: {certDisplay}");
            Console.WriteLine($"   Client Secret Fallback Enabled: {config.AllowClientSecretFallback}");
            Console.WriteLine($"   Client Secret: {secretMasked}");
        }
        else
        {
            Console.WriteLine($"   Scopes: {string.Join(", ", config.DelegatedScopes.Take(3))}...");
        }
        
        Console.WriteLine();
    }
}
