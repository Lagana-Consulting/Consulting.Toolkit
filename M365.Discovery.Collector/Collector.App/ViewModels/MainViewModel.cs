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
    private bool _useAppOnlyCertificateSignIn;
    private string _tenantId = "organizations";
    private string _certificateThumbprint = string.Empty;
    private string _certificateSubjectName = string.Empty;
    private bool _requiresReauthentication;
    private bool _isBootstrapAdminRole;

    private string _outputFolder = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
    private string _runName = $"Discovery_{DateTime.Now:yyyyMMdd_HHmm}";
    private int _reportDays = DiscoveryContext.DefaultReportDays;
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
        SignInCommand = new RelayCommandAsync(SignInAsync, CanExecuteSignIn);
        BrowseFolderCommand = new RelayCommand(BrowseFolder);
        OpenOutputFolderCommand = new RelayCommand(OpenOutputFolder);
        PreflightCommand = new RelayCommandAsync(PreflightAsync, CanExecutePreflight);
        RunSelectedCommand = new RelayCommandAsync(RunSelectedAsync, CanExecuteRunSelected);
        DeselectAllWorkloadsCommand = new RelayCommand(DeselectAllWorkloads);
        EnableEntraWorkloadsCommand = new RelayCommand(EnableEntraWorkloads);
        EnableMicrosoft365WorkloadsCommand = new RelayCommand(EnableMicrosoft365Workloads);

        // Bootstrap commands
        BootstrapSignInCommand = new RelayCommandAsync(BootstrapSignInAsync, CanExecuteBootstrapSignIn);
        CreateAppRegistrationCommand = new RelayCommandAsync(CreateAppRegistrationAsync, CanExecuteCreateAppRegistration);
        AddPermissionsCommand = new RelayCommandAsync(AddPermissionsAsync, CanExecuteAddPermissions);
        RequestAdminConsentCommand = new RelayCommand(RequestAdminConsent, CanExecuteRequestAdminConsent);
        ResetConfigCommand = new RelayCommand(ResetConfig, CanExecuteResetConfig);
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
    public IReadOnlyList<int> ReportDayOptions { get; } = DiscoveryContext.SupportedReportDays;

    // Workload counts for UI
    public string EntraIdWorkloadCount => $"({EntraIdWorkloads.Count} workloads)";
    public string Microsoft365WorkloadCount => $"({Microsoft365Workloads.Count} workloads)";

    public ICommand ConfigureAuthCommand { get; }
    public ICommand SignInCommand { get; }
    public ICommand BrowseFolderCommand { get; }
    public ICommand OpenOutputFolderCommand { get; }
    public ICommand PreflightCommand { get; }
    public ICommand RunSelectedCommand { get; }
    public ICommand DeselectAllWorkloadsCommand { get; }
    public ICommand EnableEntraWorkloadsCommand { get; }
    public ICommand EnableMicrosoft365WorkloadsCommand { get; }

    // New bootstrap commands
    public ICommand BootstrapSignInCommand { get; }
    public ICommand CreateAppRegistrationCommand { get; }
    public ICommand AddPermissionsCommand { get; }
    public ICommand RequestAdminConsentCommand { get; }
    public ICommand ResetConfigCommand { get; }

    // Help commands
    public ICommand ShowReportsPrivacyHelpCommand { get; }

    public bool IsBootstrapAdminRole
    {
        get => _isBootstrapAdminRole;
        set
        {
            if (SetProperty(ref _isBootstrapAdminRole, value))
            {
                RaisePropertyChanged(nameof(IsOperatorRole));
                RaisePropertyChanged(nameof(ActiveRoleLabel));
                RaiseCommandCanExecuteChanged();

                if (IsBootstrapAdminRole)
                {
                    Log("🔐 Role set to Bootstrap Admin. Admin setup actions are enabled; operator run actions are disabled.");
                    FooterText = "Role: Bootstrap Admin";
                }
                else
                {
                    Log("👤 Role set to Operator. Discovery actions are enabled; admin setup actions are disabled.");
                    FooterText = "Role: Operator";

                    if (HasBootstrapAdminContext())
                    {
                        RequiresReauthentication = true;
                        Log("🔄 Switched from bootstrap context. Sign in as operator before preflight/run.");
                    }
                }
            }
        }
    }

    public bool IsOperatorRole => !IsBootstrapAdminRole;

    public string ActiveRoleLabel => IsBootstrapAdminRole ? "Bootstrap Admin" : "Operator";

    public bool IsAuthenticated
    {
        get => _isAuthenticated;
        set
        {
            if (SetProperty(ref _isAuthenticated, value))
            {
                RaiseCommandCanExecuteChanged();
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
                RaiseCommandCanExecuteChanged();
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
                RaiseCommandCanExecuteChanged();
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

    public int ReportDays
    {
        get => _reportDays;
        set
        {
            var normalizedValue = DiscoveryContext.NormalizeReportDays(value);
            if (SetProperty(ref _reportDays, normalizedValue))
            {
                SaveConfiguration();
            }
        }
    }

    public string FooterText
    {
        get => _footerText;
        set => SetProperty(ref _footerText, value);
    }

    public bool RequiresReauthentication
    {
        get => _requiresReauthentication;
        private set
        {
            if (SetProperty(ref _requiresReauthentication, value))
            {
                ((RelayCommandAsync)SignInCommand).RaiseCanExecuteChanged();
            }
        }
    }

    public bool UseAppOnlyCertificateSignIn
    {
        get => _useAppOnlyCertificateSignIn;
        set
        {
            if (SetProperty(ref _useAppOnlyCertificateSignIn, value))
            {
                SaveConfiguration();
            }
        }
    }

    public string TenantId
    {
        get => _tenantId;
        set
        {
            if (SetProperty(ref _tenantId, value))
            {
                SaveConfiguration();
            }
        }
    }

    public string CertificateThumbprint
    {
        get => _certificateThumbprint;
        set
        {
            if (SetProperty(ref _certificateThumbprint, value))
            {
                SaveConfiguration();
            }
        }
    }

    public string CertificateSubjectName
    {
        get => _certificateSubjectName;
        set
        {
            if (SetProperty(ref _certificateSubjectName, value))
            {
                SaveConfiguration();
            }
        }
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

    private bool CanExecuteSignIn()
    {
        if (IsBusy || !IsOperatorRole)
        {
            return false;
        }

        return !IsAuthenticated || RequiresReauthentication || HasBootstrapAdminContext();
    }

    private bool CanExecutePreflight()
    {
        return !IsBusy && IsAuthenticated && IsOperatorRole;
    }

    private bool CanExecuteRunSelected()
    {
        return !IsBusy && IsAuthenticated && IsOperatorRole;
    }

    private bool CanExecuteBootstrapSignIn()
    {
        return !IsBusy && IsBootstrapAdminRole && (!IsAuthenticated || !HasBootstrapAdminContext());
    }

    private bool CanExecuteCreateAppRegistration()
    {
        return !IsBusy && IsBootstrapAdminRole && IsAuthenticated && !IsAppRegistered && HasBootstrapAdminContext();
    }

    private bool CanExecuteAddPermissions()
    {
        return !IsBusy && IsBootstrapAdminRole && IsAppRegistered && HasBootstrapAdminContext();
    }

    private bool CanExecuteRequestAdminConsent()
    {
        return IsBootstrapAdminRole && IsAppRegistered;
    }

    private bool CanExecuteResetConfig()
    {
        return IsBootstrapAdminRole && !IsBusy;
    }

    private void RaiseCommandCanExecuteChanged()
    {
        ((RelayCommandAsync)SignInCommand).RaiseCanExecuteChanged();
        ((RelayCommandAsync)PreflightCommand).RaiseCanExecuteChanged();
        ((RelayCommandAsync)RunSelectedCommand).RaiseCanExecuteChanged();
        ((RelayCommandAsync)BootstrapSignInCommand).RaiseCanExecuteChanged();
        ((RelayCommandAsync)CreateAppRegistrationCommand).RaiseCanExecuteChanged();
        ((RelayCommandAsync)AddPermissionsCommand).RaiseCanExecuteChanged();
        ((RelayCommand)RequestAdminConsentCommand).RaiseCanExecuteChanged();
        ((RelayCommand)ResetConfigCommand).RaiseCanExecuteChanged();
    }

    private void DeselectAllWorkloads()
    {
        foreach (var workload in Workloads)
        {
            workload.IsSelected = false;
        }
        Log("Selection updated: all workloads deselected.");
    }

    private void EnableEntraWorkloads()
    {
        foreach (var workload in EntraIdWorkloads)
        {
            workload.IsSelected = true;
        }
        Log($"Selection updated: enabled {EntraIdWorkloads.Count} Entra ID workloads.");
    }

    private void EnableMicrosoft365Workloads()
    {
        foreach (var workload in Microsoft365Workloads)
        {
            workload.IsSelected = true;
        }
        Log($"Selection updated: enabled {Microsoft365Workloads.Count} Microsoft 365 workloads.");
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
        if (!IsBootstrapAdminRole)
        {
            Log("⚠ Bootstrap admin action blocked. Switch role to Bootstrap Admin.");
            FooterText = "Role boundary: Bootstrap Admin required.";
            return;
        }

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
        if (!IsBootstrapAdminRole)
        {
            Log("⚠ Create App blocked. This action is Bootstrap Admin only.");
            FooterText = "Role boundary: Bootstrap Admin required.";
            return;
        }

        IsBusy = true;
        FooterText = "Creating app registration...";
        Log("📝 Creating app registration...");

        try
        {
            if (_graphClient == null || !HasBootstrapAdminContext())
            {
                Log("⚠ Create App requires admin bootstrap authentication.");
                Log("   Use '🔐 Admin Sign In' first (delegated token with Application.ReadWrite.All).");
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
        if (!IsBootstrapAdminRole)
        {
            Log("⚠ Add Perms blocked. This action is Bootstrap Admin only.");
            FooterText = "Role boundary: Bootstrap Admin required.";
            return;
        }

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

            if (!HasBootstrapAdminContext())
            {
                Log("⚠ Add Perms requires admin bootstrap authentication.");
                Log("   Current auth is collector/runtime context.");
                Log("   Use '🔐 Admin Sign In' first, then run Add Perms.");
                FooterText = "Admin sign-in required.";
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

            Log($"   Delegated permissions - added: {result.AddedDelegatedCount}, existing: {result.ExistingDelegatedCount}");
            Log($"   Application permissions - added: {result.AddedApplicationCount}, existing: {result.ExistingApplicationCount}");

            if (result.Unresolved.Length > 0)
            {
                Log("⚠ Unresolved permissions (not found as Graph scope/role):");
                foreach (var perm in result.Unresolved)
                {
                    Log($"   - {perm}");
                }
            }

            if (!string.IsNullOrWhiteSpace(_clientId) && _tokenInfo != null)
            {
                var profiles = appService.GetConsentProfiles(_clientId, _tokenInfo.TenantId);
                Log("🔐 Consent profiles:");
                foreach (var profile in profiles)
                {
                    Log($"   [{profile.Name}]");
                    Log($"   Permissions: {string.Join(", ", profile.Permissions)}");
                    Log($"   Consent URL: {profile.AdminConsentUrl}");
                }
            }

            RequiresReauthentication = true;
            Log("🔄 Permission state changed. Re-authentication is required before preflight/run.");

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
        if (!IsBootstrapAdminRole)
        {
            Log("⚠ Consent blocked. This action is Bootstrap Admin only.");
            FooterText = "Role boundary: Bootstrap Admin required.";
            return;
        }

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
            RequiresReauthentication = true;
            Log("🔄 Re-authentication required after consent to refresh token permissions.");
            FooterText = "Admin consent requested - check browser.";
        }
        catch (Exception ex)
        {
            Log($"❌ Failed to request admin consent: {ex.Message}");
        }
    }

    private async Task SignInAsync()
    {
        if (!IsOperatorRole)
        {
            Log("⚠ Operator sign-in blocked. Switch role to Operator for runtime discovery.");
            FooterText = "Role boundary: Operator required.";
            return;
        }

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
            AuthConfig config;

            if (UseAppOnlyCertificateSignIn)
            {
                if (string.IsNullOrWhiteSpace(TenantId) || TenantId.Equals("organizations", StringComparison.OrdinalIgnoreCase))
                {
                    Log("❌ App-only sign-in requires a specific Tenant ID (GUID or verified domain), not 'organizations'.");
                    FooterText = "Invalid app-only tenant ID.";
                    return;
                }

                if (!string.IsNullOrWhiteSpace(CertificateThumbprint) && !string.IsNullOrWhiteSpace(CertificateSubjectName))
                {
                    Log("❌ Set either Certificate Thumbprint or Certificate Subject, not both.");
                    FooterText = "Invalid certificate settings.";
                    return;
                }

                if (string.IsNullOrWhiteSpace(CertificateThumbprint) && string.IsNullOrWhiteSpace(CertificateSubjectName))
                {
                    Log("❌ App-only certificate sign-in requires Certificate Thumbprint or Certificate Subject.");
                    FooterText = "Certificate details required.";
                    return;
                }

                config = !string.IsNullOrWhiteSpace(CertificateThumbprint)
                    ? AuthConfig.CreateAppOnlyWithCertificateByThumbprint(_clientId!, TenantId, CertificateThumbprint)
                    : AuthConfig.CreateAppOnlyWithCertificateBySubject(_clientId!, TenantId, CertificateSubjectName);

                Log("📋 Using app-only certificate authentication.");
            }
            else
            {
                Log($"📋 Requesting {requiredPermissions.Length} delegated permission(s): {string.Join(", ", requiredPermissions)}");
                config = new AuthConfig
                {
                    Mode = AuthMode.InteractiveDelegated,
                    ClientId = _clientId,
                    TenantId = string.IsNullOrWhiteSpace(TenantId) ? "organizations" : TenantId,
                    DelegatedScopes = requiredPermissions
                };
            }

            var factory = new GraphClientFactory(config);
            var (client, tokenInfo) = await factory.CreateAuthenticatedClientAsync();

            _graphClient = new ResilientGraphClient(client);
            _tokenInfo = tokenInfo;
            _preflight = new PreflightService(_graphClient);  // ✅ Initializes _preflight

            IsAuthenticated = true;

            Log($"✅ Signed in as {tokenInfo.Username}");
            Log($"   Tenant: {tokenInfo.TenantId}");
            if (!string.IsNullOrWhiteSpace(tokenInfo.AuthenticationPath))
            {
                Log($"   Auth path: {tokenInfo.AuthenticationPath}");
            }
            Log($"   Permissions granted: {string.Join(", ", tokenInfo.GrantedScopes)}");
            if (UseAppOnlyCertificateSignIn && tokenInfo.ApplicationRoles.Length == 0)
            {
                Log("⚠ App-only token did not include Graph app role claims (roles).");
                Log("   Check that APPLICATION permissions were added and admin consented on the app registration.");
            }
            RequiresReauthentication = false;
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
        if (!IsOperatorRole)
        {
            Log("⚠ Preflight blocked. Switch role to Operator.");
            FooterText = "Role boundary: Operator required.";
            return;
        }

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

            if (RequiresReauthentication)
            {
                Log("⚠ Re-authentication required before preflight. Sign in again to refresh granted permissions.");
                FooterText = "Re-authentication required.";
                return;
            }

            var report = await _preflight.RunPreflightAsync(_tokenInfo);

            Log($"✅ {report.OrganizationTestMessage}");

            var ctx = new DiscoveryContext(OutputFolder, RunName, ReportDays);

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
        if (!IsOperatorRole)
        {
            Log("⚠ Discovery run blocked. Switch role to Operator.");
            FooterText = "Role boundary: Operator required.";
            return;
        }

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

            if (RequiresReauthentication)
            {
                Log("⚠ Re-authentication required before run. Sign in again to refresh granted permissions.");
                FooterText = "Re-authentication required.";
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

            var ctx = new DiscoveryContext(runFolder, RunName, ReportDays);

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
                { "entra.authMethods", new AuthMethodsCoverageCollector(_graphClient) },
                { "entra.directorySettings", new DirectorySettingsCollector(_graphClient) },
                { "hybrid.aadConnectConfig", new HybridAadConnectConfigCollector(_graphClient) },
    
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
                AppObjectId = _appObjectId,
                ReportDays,
                UseAppOnlyCertificateSignIn,
                TenantId,
                CertificateThumbprint,
                CertificateSubjectName
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
                var config = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(json);

                if (config != null)
                {
                    if (config.TryGetValue("ClientId", out var clientId))
                    {
                        var loadedClientId = clientId.ValueKind == JsonValueKind.String ? clientId.GetString() : null;
                        if (!string.IsNullOrWhiteSpace(loadedClientId))
                        {
                            _clientId = loadedClientId;
                            Log($"✅ Loaded saved Client ID: {_clientId.Substring(0, 8)}...");
                        }
                    }

                    if (config.TryGetValue("AppObjectId", out var objectId))
                    {
                        var loadedObjectId = objectId.ValueKind == JsonValueKind.String ? objectId.GetString() : null;
                        _appObjectId = loadedObjectId;
                        // Only set IsAppRegistered if we have both IDs
                        // The app can verify later when authenticated
                        if (!string.IsNullOrEmpty(_clientId) && !string.IsNullOrEmpty(_appObjectId))
                        {
                            IsAppRegistered = true;
                            Log($"   App Object ID loaded (not verified)");
                        }
                    }

                    if (config.TryGetValue("UseAppOnlyCertificateSignIn", out var appOnlyValue))
                    {
                        if (appOnlyValue.ValueKind == JsonValueKind.True || appOnlyValue.ValueKind == JsonValueKind.False)
                        {
                            _useAppOnlyCertificateSignIn = appOnlyValue.GetBoolean();
                        }
                        else if (appOnlyValue.ValueKind == JsonValueKind.String &&
                                 bool.TryParse(appOnlyValue.GetString(), out var parsedAppOnly))
                        {
                            _useAppOnlyCertificateSignIn = parsedAppOnly;
                        }
                    }

                    if (config.TryGetValue("ReportDays", out var reportDays))
                    {
                        if (reportDays.ValueKind == JsonValueKind.Number && reportDays.TryGetInt32(out var parsedReportDays))
                        {
                            _reportDays = DiscoveryContext.NormalizeReportDays(parsedReportDays);
                        }
                        else if (reportDays.ValueKind == JsonValueKind.String &&
                                 int.TryParse(reportDays.GetString(), out parsedReportDays))
                        {
                            _reportDays = DiscoveryContext.NormalizeReportDays(parsedReportDays);
                        }
                    }

                    if (config.TryGetValue("TenantId", out var tenantId))
                    {
                        var loadedTenantId = tenantId.ValueKind == JsonValueKind.String ? tenantId.GetString() : null;
                        if (!string.IsNullOrWhiteSpace(loadedTenantId))
                        {
                            _tenantId = loadedTenantId;
                        }
                    }

                    if (config.TryGetValue("CertificateThumbprint", out var thumbprint))
                    {
                        if (thumbprint.ValueKind == JsonValueKind.String)
                        {
                            _certificateThumbprint = thumbprint.GetString() ?? string.Empty;
                        }
                    }

                    if (config.TryGetValue("CertificateSubjectName", out var subjectName))
                    {
                        if (subjectName.ValueKind == JsonValueKind.String)
                        {
                            _certificateSubjectName = subjectName.GetString() ?? string.Empty;
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
        if (!IsBootstrapAdminRole)
        {
            Log("⚠ Reset blocked. This action is Bootstrap Admin only.");
            FooterText = "Role boundary: Bootstrap Admin required.";
            return;
        }

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
            _reportDays = DiscoveryContext.DefaultReportDays;
            _useAppOnlyCertificateSignIn = false;
            _tenantId = "organizations";
            _certificateThumbprint = string.Empty;
            _certificateSubjectName = string.Empty;
            RequiresReauthentication = false;
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

    private bool HasBootstrapAdminContext()
    {
        if (_tokenInfo == null)
        {
            return false;
        }

        if (_tokenInfo.AuthMode != AuthMode.InteractiveDelegated)
        {
            return false;
        }

        return _tokenInfo.GrantedScopes.Contains("Application.ReadWrite.All", StringComparer.OrdinalIgnoreCase);
    }
}
