using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Windows.Input;
using Collector.App.Services;
using Collector.Core;
using Collector.Core.Collectors;
using Collector.Core.Output;
using Collector.Export;
using Collector.Graph;
using Collector.Graph.Auth;

namespace Collector.App.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly StringBuilder _log = new();
    private readonly WorkloadCatalog _catalog = WorkloadCatalog.CreateDefault();
    private readonly CsvExportService _export = new();

    private ResilientGraphClient? _graphClient;
    private PreflightService? _preflight;
    private TokenInfo? _tokenInfo;
    private string? _clientId;
    private string? _appObjectId;
    private bool _isAuthenticated;
    private bool _isAppRegistered;

    private string _outputFolder = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    private string _runName = $"Discovery_{DateTime.Now:yyyyMMdd_HHmm}";
    private string _footerText = "Ready.";
    private bool _isBusy;

    public event PropertyChangedEventHandler? PropertyChanged;

    public MainViewModel()
    {
        Workloads = new ObservableCollection<WorkloadViewModel>(_catalog.Workloads.Select(w => new WorkloadViewModel(w)));
        Jobs = new ObservableCollection<JobRowViewModel>();

        // Group workloads by service type
        EntraIdWorkloads = new ObservableCollection<WorkloadViewModel>(
            Workloads.Where(w => w.Definition.Category == "Entra ID"));
        
        Microsoft365Workloads = new ObservableCollection<WorkloadViewModel>(
            Workloads.Where(w => w.Definition.Category == "Microsoft 365"));
        
        OrganizationWorkloads = new ObservableCollection<WorkloadViewModel>(
            Workloads.Where(w => w.Definition.Category == "Organization"));

        ConfigureAuthCommand = new RelayCommand(ConfigureAuth);
        SignInCommand = new RelayCommandAsync(SignInAsync, () => !IsBusy && !IsAuthenticated);
        BrowseFolderCommand = new RelayCommand(BrowseFolder);
        OpenOutputFolderCommand = new RelayCommand(OpenOutputFolder);
        PreflightCommand = new RelayCommandAsync(PreflightAsync, () => !IsBusy && IsAuthenticated);
        RunSelectedCommand = new RelayCommandAsync(RunSelectedAsync, () => !IsBusy && IsAuthenticated);

        // Bootstrap commands
        BootstrapSignInCommand = new RelayCommandAsync(BootstrapSignInAsync, () => !IsBusy && !IsAuthenticated);
        CreateAppRegistrationCommand = new RelayCommandAsync(CreateAppRegistrationAsync, () => !IsBusy && IsAuthenticated && !IsAppRegistered);
        AddPermissionsCommand = new RelayCommandAsync(AddPermissionsAsync, () => !IsBusy && IsAppRegistered);
        RequestAdminConsentCommand = new RelayCommand(RequestAdminConsent, () => IsAppRegistered);
        ResetConfigCommand = new RelayCommand(ResetConfig);
        ShowReportsPrivacyHelpCommand = new RelayCommand(ShowReportsPrivacyHelp);

        // Load saved configuration
        LoadConfiguration();
    }

    public ObservableCollection<WorkloadViewModel> Workloads { get; }
    public ObservableCollection<JobRowViewModel> Jobs { get; }

    // Grouped workload collections by service type
    public ObservableCollection<WorkloadViewModel> EntraIdWorkloads { get; }
    public ObservableCollection<WorkloadViewModel> Microsoft365Workloads { get; }
    public ObservableCollection<WorkloadViewModel> OrganizationWorkloads { get; }

    // Workload counts for UI
    public string EntraIdWorkloadCount => $"({EntraIdWorkloads.Count} workloads)";
    public string Microsoft365WorkloadCount => $"({Microsoft365Workloads.Count} workloads)";

    public ICommand ConfigureAuthCommand { get; }
    public ICommand SignInCommand { get; }
    public ICommand BrowseFolderCommand { get; }
    public ICommand OpenOutputFolderCommand { get; }
    public ICommand PreflightCommand { get; }
    public ICommand RunSelectedCommand { get; }

    // New bootstrap commands
    public ICommand BootstrapSignInCommand { get; }
    public ICommand CreateAppRegistrationCommand { get; }
    public ICommand AddPermissionsCommand { get; }
    public ICommand RequestAdminConsentCommand { get; }
    public ICommand ResetConfigCommand { get; }

    // Help commands
    public ICommand ShowReportsPrivacyHelpCommand { get; }

    public bool IsAuthenticated
    {
        get => _isAuthenticated;
        set
        {
            if (SetProperty(ref _isAuthenticated, value))
            {
                ((RelayCommandAsync)SignInCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)PreflightCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)RunSelectedCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)BootstrapSignInCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)CreateAppRegistrationCommand).RaiseCanExecuteChanged();
            }
        }
    }

    public bool IsAppRegistered
    {
        get => _isAppRegistered;
        set
        {
            if (SetProperty(ref _isAppRegistered, value))
            {
                ((RelayCommandAsync)CreateAppRegistrationCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)AddPermissionsCommand).RaiseCanExecuteChanged();
                ((RelayCommand)RequestAdminConsentCommand).RaiseCanExecuteChanged();
            }
        }
    }

    public bool IsBusy
    {
        get => _isBusy;
        set
        {
            if (SetProperty(ref _isBusy, value))
            {
                ((RelayCommandAsync)SignInCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)PreflightCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)RunSelectedCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)BootstrapSignInCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)CreateAppRegistrationCommand).RaiseCanExecuteChanged();
                ((RelayCommandAsync)AddPermissionsCommand).RaiseCanExecuteChanged();
            }
        }
    }

    public string OutputFolder
    {
        get => _outputFolder;
        set => SetProperty(ref _outputFolder, value);
    }

    public string RunName
    {
        get => _runName;
        set => SetProperty(ref _runName, value);
    }

    public string FooterText
    {
        get => _footerText;
        set => SetProperty(ref _footerText, value);
    }

    public string LogText => _log.ToString();

    private void Log(string message)
    {
        _log.AppendLine($"[{DateTime.Now:HH:mm:ss}] {message}");
        RaisePropertyChanged(nameof(LogText));
    }

    private bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
            return false;

        field = value;
        RaisePropertyChanged(propertyName);
        return true;
    }

    private void RaisePropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private void ConfigureAuth()
    {
        // Get required permissions based on selected workloads
        var selectedKeys = Workloads.Where(w => w.IsSelected).Select(w => w.Key).ToList();
        if (selectedKeys.Count == 0)
        {
            // Default to showing permissions for default selected workloads
            selectedKeys = Workloads.Where(w => w.Definition.IsDefaultSelected).Select(w => w.Key).ToList();
        }

        var requiredPermissions = _catalog.GetRequiredPermissionsForKeys(selectedKeys);

        // Open settings window
        var settingsWindow = new Views.SettingsWindow(requiredPermissions, _clientId)
        {
            Owner = System.Windows.Application.Current.MainWindow
        };

        if (settingsWindow.ShowDialog() == true)
        {
            _clientId = settingsWindow.ClientId;
            Log($"✅ Client ID configured: {_clientId.Substring(0, 8)}...");

            // Save to configuration file
            SaveConfiguration();
        }
    }

    private void BrowseFolder()
    {
        using var dlg = new FolderBrowserDialog();
        dlg.Description = "Choose an output folder for CSV exports";
        dlg.UseDescriptionForTitle = true;
        dlg.SelectedPath = OutputFolder;

        if (dlg.ShowDialog() == DialogResult.OK && Directory.Exists(dlg.SelectedPath))
            OutputFolder = dlg.SelectedPath;
    }

    private void OpenOutputFolder()
    {
        try
        {
            if (!Directory.Exists(OutputFolder))
                Directory.CreateDirectory(OutputFolder);

            Process.Start(new ProcessStartInfo
            {
                FileName = OutputFolder,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Log($"Open folder failed: {ex.Message}");
        }
    }

    private async Task BootstrapSignInAsync()
    {
        IsBusy = true;
        FooterText = "Signing in as admin...";
        Log("🔐 Starting admin authentication for app registration setup...");

        try
        {
            var config = new AuthConfig
            {
                Mode = AuthMode.InteractiveDelegated,
                ClientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e", // Microsoft Graph PowerShell (well-known)
                TenantId = "organizations",
                DelegatedScopes = new[] { "Application.ReadWrite.All", "User.Read" }
            };

            var factory = new GraphClientFactory(config);
            var (client, tokenInfo) = await factory.CreateAuthenticatedClientAsync();

            _graphClient = new ResilientGraphClient(client);
            _tokenInfo = tokenInfo;
            _preflight = new PreflightService(_graphClient);  // ✅ Now initialized

            IsAuthenticated = true;
            Log($"✅ Admin signed in as {tokenInfo.Username}");
            FooterText = $"Admin signed in: {tokenInfo.Username}";
        }
        catch (Exception ex)
        {
            Log($"❌ Admin sign-in failed: {ex.Message}");
            FooterText = "Admin sign-in failed.";
            IsAuthenticated = false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task CreateAppRegistrationAsync()
    {
        IsBusy = true;
        FooterText = "Creating app registration...";
        Log("📝 Creating app registration...");

        try
        {
            if (_graphClient == null)
            {
                Log("⚠ Not authenticated. Sign in with Global Admin first.");
                return;
            }

            var appService = new AppRegistrationService(_graphClient.Client);
            var appName = $"M365 Discovery Collector - {DateTime.Now:yyyyMMdd}";

            var (clientId, objectId) = await appService.CreateAppRegistrationAsync(appName);

            _clientId = clientId;
            _appObjectId = objectId;
            IsAppRegistered = true;

            Log($"✅ App registration created successfully!");
            Log($"   Client ID: {clientId}");
            Log($"   Object ID: {objectId}");
            Log($"   Display Name: {appName}");

            SaveConfiguration();
            FooterText = "App registration created.";
        }
        catch (Exception ex)
        {
            Log($"❌ Failed to create app registration: {ex.Message}");
            FooterText = "App creation failed.";
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task AddPermissionsAsync()
    {
        IsBusy = true;
        FooterText = "Adding permissions...";
        Log("🔑 Adding required permissions...");

        try
        {
            if (_graphClient == null || string.IsNullOrEmpty(_appObjectId))
            {
                Log("⚠ App registration not available.");
                return;
            }

            var selectedKeys = Workloads.Where(w => w.IsSelected).Select(w => w.Key).ToList();
            if (selectedKeys.Count == 0)
            {
                selectedKeys = Workloads.Where(w => w.Definition.IsDefaultSelected).Select(w => w.Key).ToList();
            }

            var requiredPermissions = _catalog.GetRequiredPermissionsForKeys(selectedKeys);

            Log($"   Selected workloads: {selectedKeys.Count}");
            Log($"   Requested permissions: {requiredPermissions.Length}");

            var appService = new AppRegistrationService(_graphClient.Client);
            var result = await appService.AddPermissionsAsync(_appObjectId, requiredPermissions);

            if (result.AlreadyExisted.Length > 0)
            {
                Log($"✓ Already had {result.AlreadyExisted.Length} permission(s):");
                foreach (var perm in result.AlreadyExisted)
                {
                    Log($"   - {perm}");
                }
            }

            if (result.NewlyAdded.Length > 0)
            {
                Log($"✅ Added {result.NewlyAdded.Length} new permission(s):");
                foreach (var perm in result.NewlyAdded)
                {
                    Log($"   - {perm}");
                }
            }
            else
            {
                Log("ℹ No new permissions needed - all already configured.");
            }

            FooterText = $"Permissions updated: {result.NewlyAdded.Length} added, {result.AlreadyExisted.Length} already existed.";
        }
        catch (Exception ex)
        {
            Log($"❌ Failed to add permissions: {ex.Message}");
            FooterText = "Permission update failed.";
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void RequestAdminConsent()
    {
        try
        {
            if (string.IsNullOrEmpty(_clientId) || _tokenInfo == null)
            {
                Log("⚠ App registration or authentication not available.");
                return;
            }

            // Verify permissions were added
            if (_graphClient == null || string.IsNullOrEmpty(_appObjectId))
            {
                Log("⚠ Cannot verify permissions. Please use Azure Portal to grant consent:");
                Log($"   1. Go to portal.azure.com → Azure AD → App Registrations");
                Log($"   2. Find app with Client ID: {_clientId}");
                Log($"   3. Click 'API Permissions' → 'Grant admin consent'");
                return;
            }

            var appService = new AppRegistrationService(_graphClient.Client);
            var consentUrl = appService.GetAdminConsentUrl(_clientId, _tokenInfo.TenantId);

            Log("🌐 Opening admin consent URL in browser...");
            Log($"   Client ID: {_clientId}");
            Log($"   Tenant ID: {_tokenInfo.TenantId}");
            Log("");
            Log("⚠ IMPORTANT: If you see an error about invalid claims:");
            Log("   1. Wait 30-60 seconds for Azure AD replication");
            Log("   2. Go to portal.azure.com → Azure AD → App Registrations");
            Log($"   3. Find your app and verify API Permissions are listed");
            Log("   4. Click 'Grant admin consent for [tenant]' button");
            Log("");
            Log($"   Consent URL: {consentUrl}");

            Process.Start(new ProcessStartInfo
            {
                FileName = consentUrl,
                UseShellExecute = true
            });

            Log("");
            Log("⚠ After granting consent:");
            Log("   - The 'localhost refused' error is NORMAL (ignore it)");
            Log("   - You can close the browser");
            Log("   - Permissions are now granted!");
            FooterText = "Admin consent requested - check browser.";
        }
        catch (Exception ex)
        {
            Log($"❌ Failed to request admin consent: {ex.Message}");
        }
    }

    private async Task SignInAsync()
    {
        if (string.IsNullOrWhiteSpace(_clientId))
        {
            Log("⚠ App registration not configured. Opening configuration dialog...");
            ConfigureAuth();

            if (string.IsNullOrWhiteSpace(_clientId))
            {
                Log("❌ Sign-in cancelled - no Client ID configured.");
                return;
            }
        }

        IsBusy = true;
        FooterText = "Signing in...";
        Log("🔐 Starting authentication...");

        try
        {
            var selectedKeys = Workloads.Where(w => w.IsSelected).Select(w => w.Key).ToList();
            if (selectedKeys.Count == 0)
            {
                Log("⚠ No workloads selected. Using default workloads for permission scope.");
                selectedKeys = Workloads.Where(w => w.Definition.IsDefaultSelected).Select(w => w.Key).ToList();
            }

            var requiredPermissions = _catalog.GetRequiredPermissionsForKeys(selectedKeys);

            Log($"📋 Requesting {requiredPermissions.Length} permission(s): {string.Join(", ", requiredPermissions)}");

            var config = new AuthConfig
            {
                Mode = AuthMode.InteractiveDelegated,
                ClientId = _clientId,
                TenantId = "organizations",
                DelegatedScopes = requiredPermissions
            };

            var factory = new GraphClientFactory(config);
            var (client, tokenInfo) = await factory.CreateAuthenticatedClientAsync();

            _graphClient = new ResilientGraphClient(client);
            _tokenInfo = tokenInfo;
            _preflight = new PreflightService(_graphClient);  // ✅ Initializes _preflight

            IsAuthenticated = true;

            Log($"✅ Signed in as {tokenInfo.Username}");
            Log($"   Tenant: {tokenInfo.TenantId}");
            Log($"   Scopes granted: {string.Join(", ", tokenInfo.GrantedScopes)}");
            FooterText = $"Signed in as {tokenInfo.Username}";
        }
        catch (Exception ex)
        {
            Log($"❌ Sign-in failed: {ex.Message}");
            FooterText = "Sign-in failed.";
            IsAuthenticated = false;
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task PreflightAsync()
    {
        IsBusy = true;
        FooterText = "Preflight running...";
        Log("Preflight check started.");

        try
        {
            if (_preflight == null || _graphClient == null || _tokenInfo == null)
            {
                Log("⚠ Graph client not initialized. Authenticate first.");
                FooterText = "Not authenticated.";
                return;
            }

            var report = await _preflight.RunPreflightAsync(_tokenInfo);

            Log($"✅ {report.OrganizationTestMessage}");

            var ctx = new DiscoveryContext(OutputFolder, RunName);

            foreach (var w in Workloads)
            {
                var result = await _preflight.CheckAsync(ctx, w.Key);
                w.Status = result.Status;
                w.LastPreflightMessage = result.Message;
                Log($"  {w.DisplayName}: {result.Message}");
            }

            Log("Preflight completed.");
            FooterText = "Preflight done.";
        }
        catch (Exception ex)
        {
            Log($"Preflight error: {ex.Message}");
            FooterText = "Preflight failed.";
        }
        finally
        {
            IsBusy = false;
        }
    }

    private async Task RunSelectedAsync()
    {
        IsBusy = true;
        FooterText = "Discovery running...";
        Log("🚀 Discovery started.");

        try
        {
            if (_graphClient == null || _tokenInfo == null)
            {
                Log("⚠ Not authenticated. Sign in first.");
                FooterText = "Not authenticated.";
                return;
            }

            var runFolder = Path.Combine(OutputFolder, RunName);
            Directory.CreateDirectory(runFolder);

            var selected = Workloads.Where(w => w.IsSelected).ToList();
            if (selected.Count == 0)
            {
                Log("⚠ No workloads selected.");
                FooterText = "Nothing selected.";
                return;
            }

            Log($"📁 Output folder: {runFolder}");
            Log($"📊 Collecting {selected.Count} workload(s)...");
            Log("");

            var ctx = new DiscoveryContext(runFolder, RunName);

            // Initialize output manager with preflight report
            var preflightReport = await _preflight!.RunPreflightAsync(_tokenInfo);
            var outputManager = new OutputManager(ctx, preflightReport);

            // Map workload keys to collectors
            var collectorMap = new Dictionary<string, IWorkloadCollector>
            {
                // === V2 - MIGRATION RISK FLAGS ===
                { "entra.conditionalAccess", new ConditionalAccessCollector(_graphClient) },
                { "entra.crossTenantAccess", new CrossTenantAccessCollector(_graphClient) },
                { "entra.guests", new GuestUsersCollector(_graphClient) },
                { "entra.groupInventoryPlus", new GroupInventoryPlusCollector(_graphClient) },
                { "entra.appCredentials", new AppCredentialsCollector(_graphClient) },
                { "entra.appAssignments", new AppAssignmentsCollector(_graphClient) },
                { "entra.signInSignals", new SignInSignalsCollector(_graphClient) },
                { "entra.directorySettings", new DirectorySettingsCollector(_graphClient) },
    
                // === V1 - Core Entra Directory ===
                { "entra.users", new EntraUsersCollector(_graphClient) },
                { "entra.groups", new EntraGroupsCollector(_graphClient) },
                { "entra.applications", new EntraApplicationsCollector(_graphClient) },
                { "entra.servicePrincipals", new EntraServicePrincipalsCollector(_graphClient) },
                { "entra.roles", new EntraRolesCollector(_graphClient) },
    
                // === V1 - Organization & Usage Reports ===
                { "org.organization", new OrganizationCollector(_graphClient) },
                { "usage.onedrive", new OneDriveUsageCollector(_graphClient) },
                { "usage.sharepoint", new SharePointUsageCollector(_graphClient) },
                { "usage.teams", new TeamsActivityCollector(_graphClient) },
                { "usage.exchange", new ExchangeMailboxUsageCollector(_graphClient) },
                { "m365.groups", new M365GroupsCollector(_graphClient) }
            };

            // Run each selected collector
            foreach (var workload in selected)
            {
                if (!collectorMap.TryGetValue(workload.Key, out var collector))
                {
                    Log($"⚠ No collector found for: {workload.DisplayName}");
                    continue;
                }

                Log($"▶ Collecting {workload.DisplayName}...");

                try
                {
                    var progress = new Progress<string>(msg => Log($"  {msg}"));
                    var result = await collector.CollectAsync(ctx, progress, CancellationToken.None);
                    outputManager.AddResult(result);

                    var statusIcon = result.Success ? "✅" : "❌";
                    var confidenceIcon = result.ConfidenceLevel switch
                    {
                        ConfidenceLevel.Authoritative => "🟢",
                        ConfidenceLevel.Partial => "🟡",
                        ConfidenceLevel.Unavailable => "🔴",
                        _ => "⚪"
                    };

                    Log($"  {statusIcon} {confidenceIcon} {result.Message}");

                    if (result.ItemCount > 0)
                    {
                        Log($"  📊 Collected {result.ItemCount} item(s)");
                    }
                }
                catch (Exception ex)
                {
                    Log($"  ❌ Error: {ex.Message}");
                }

                Log("");
            }

            // Finalize outputs (writes CSV files)
            Log("📝 Generating output files...");
            await outputManager.FinalizeAsync(CancellationToken.None);

            Log($"✅ Discovery complete!");
            Log($"📂 Output folder: {runFolder}");
            FooterText = "Discovery complete.";
        }
        catch (Exception ex)
        {
            Log($"❌ Discovery error: {ex.Message}");
            Log($"   Stack: {ex.StackTrace}");
            FooterText = "Discovery failed.";
        }
        finally
        {
            IsBusy = false;
        }
    }

    private void SaveConfiguration()
    {
        try
        {
            var configPath = GetConfigPath();
            Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);

            var config = new
            {
                ClientId = _clientId,
                AppObjectId = _appObjectId
            };
            var json = JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(configPath, json);

            Log($"💾 Configuration saved.");
        }
        catch (Exception ex)
        {
            Log($"⚠ Failed to save configuration: {ex.Message}");
        }
    }

    private void LoadConfiguration()
    {
        try
        {
            var configPath = GetConfigPath();
            if (File.Exists(configPath))
            {
                var json = File.ReadAllText(configPath);
                var config = JsonSerializer.Deserialize<Dictionary<string, string>>(json);

                if (config != null)
                {
                    if (config.TryGetValue("ClientId", out var clientId))
                    {
                        _clientId = clientId;
                        Log($"✅ Loaded saved Client ID: {_clientId.Substring(0, 8)}...");
                    }

                    if (config.TryGetValue("AppObjectId", out var objectId))
                    {
                        _appObjectId = objectId;
                        // Only set IsAppRegistered if we have both IDs
                        // The app can verify later when authenticated
                        if (!string.IsNullOrEmpty(_clientId) && !string.IsNullOrEmpty(_appObjectId))
                        {
                            IsAppRegistered = true;
                            Log($"   App Object ID loaded (not verified)");
                        }
                    }
                }
            }
        }
        catch
        {
            // Ignore errors loading config
        }
    }

    private static string GetConfigPath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "M365DiscoveryCollector",
            "config.json"
        );
    }

    private void ResetConfig()
    {
        try
        {
            var configPath = GetConfigPath();
            if (File.Exists(configPath))
            {
                File.Delete(configPath);
                Log("🔄 Configuration reset. Please restart the application.");
            }

            _clientId = null;
            _appObjectId = null;
            IsAppRegistered = false;
            IsAuthenticated = false;

            FooterText = "Configuration cleared.";
        }
        catch (Exception ex)
        {
            Log($"❌ Failed to reset config: {ex.Message}");
        }
    }

    private void ShowReportsPrivacyHelp()
    {
        try
        {
            Log("ℹ️ About Obfuscated Report Data (Hashed Usernames)");
            Log("");
            Log("If you see hashed values like 'E9112DECD6A8E67384A17E3739864369' instead of");
            Log("actual usernames, your tenant has display name concealment enabled.");
            Log("");
            Log("📋 What this means:");
            Log("   • User-identifiable information is replaced with hashes for privacy");
            Log("   • Affects: User Principal Names, Display Names, Email Addresses");
            Log("   • Reports still show accurate usage metrics and counts");
            Log("");
            Log("🔧 To disable display name concealment:");
            Log("   1. Go to Microsoft 365 Admin Center (admin.microsoft.com)");
            Log("   2. Navigate to: Settings → Org settings → Services");
            Log("   3. Click 'Reports'");
            Log("   4. Uncheck 'Display concealed user, group, and site names in all reports'");
            Log("   5. Save changes");
            Log("");
            Log("⚠️ Note: Only Global Administrators can change this setting");
            Log("         Changes may take a few hours to reflect in reports");
            Log("");
            Log("📖 Opening Microsoft documentation in browser...");

            // Open Microsoft's documentation
            var docsUrl = "https://learn.microsoft.com/en-us/microsoft-365/admin/activity-reports/activity-reports?view=o365-worldwide#show-user-details-in-the-reports";

            System.Diagnostics.Process.Start(new ProcessStartInfo
            {
                FileName = docsUrl,
                UseShellExecute = true
            });

            FooterText = "Reports privacy help displayed.";
        }
        catch (Exception ex)
        {
            Log($"❌ Failed to open help: {ex.Message}");
        }
    }
}