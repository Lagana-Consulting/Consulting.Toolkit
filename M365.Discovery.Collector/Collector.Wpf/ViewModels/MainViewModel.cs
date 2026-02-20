using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Collector.Core;
using Collector.Graph;
using Collector.Wpf.Models;
using System.Collections.ObjectModel;
using System.IO;
using System.Windows;

namespace Collector.Wpf.ViewModels;

public partial class MainViewModel : ObservableObject
{
    [ObservableProperty]
    private bool _isInteractiveDelegated = true;

    [ObservableProperty]
    private bool _isAppOnly;

    [ObservableProperty]
    private string _clientId = string.Empty;

    [ObservableProperty]
    private string _tenantId = string.Empty;

    [ObservableProperty]
    private string _clientSecret = string.Empty;

    [ObservableProperty]
    private string _outputFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "M365Discovery");

    [ObservableProperty]
    private bool _isRunning;

    [ObservableProperty]
    private bool _isCompleted;

    [ObservableProperty]
    private string _statusMessage = "Ready to start discovery";

    [ObservableProperty]
    private int _progressPercentage;

    [ObservableProperty]
    private string _currentActivity = string.Empty;

    [ObservableProperty]
    private ObservableCollection<string> _logMessages = new();

    public ObservableCollection<WorkloadItem> Workloads { get; } = new(WorkloadItem.GetAvailableWorkloads());

    public MainViewModel()
    {
        Workloads = new ObservableCollection<WorkloadViewModel>(_catalog.Workloads.Select(w => new WorkloadViewModel(w)));
        Jobs = new ObservableCollection<JobRowViewModel>();

        ConfigureAuthCommand = new RelayCommand(ConfigureAuth);
        SignInCommand = new RelayCommandAsync(SignInAsync, () => !IsBusy && !IsAuthenticated);
        BrowseFolderCommand = new RelayCommand(BrowseFolder);
        OpenOutputFolderCommand = new RelayCommand(OpenOutputFolder);
        PreflightCommand = new RelayCommandAsync(PreflightAsync, () => !IsBusy && IsAuthenticated);
        RunSelectedCommand = new RelayCommandAsync(RunSelectedAsync, () => !IsBusy && IsAuthenticated);
        TestReportsApiCommand = new RelayCommandAsync(TestReportsApiAsync, () => !IsBusy && IsAuthenticated);
        
        // New bootstrap commands
        BootstrapSignInCommand = new RelayCommandAsync(BootstrapSignInAsync, () => !IsBusy && !IsAuthenticated);
        CreateAppRegistrationCommand = new RelayCommandAsync(CreateAppRegistrationAsync, () => !IsBusy && IsAuthenticated && !IsAppRegistered);
        AddPermissionsCommand = new RelayCommandAsync(AddPermissionsAsync, () => !IsBusy && IsAppRegistered);
        RequestAdminConsentCommand = new RelayCommand(RequestAdminConsent, () => IsAppRegistered);

        // Help commands
        ShowReportsPrivacyHelpCommand = new RelayCommand(ShowReportsPrivacyHelp);

        // Load saved configuration
        LoadConfiguration();

        ResetConfigCommand = new RelayCommand(ResetConfig);
    }

    [RelayCommand]
    private void SelectAllWorkloads()
    {
        foreach (var workload in Workloads)
        {
            workload.IsSelected = true;
        }
    }

    [RelayCommand]
    private void DeselectAllWorkloads()
    {
        foreach (var workload in Workloads)
        {
            workload.IsSelected = false;
        }
    }

    [RelayCommand]
    private void BrowseOutputFolder()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Title = "Select Output Folder",
            FileName = "Select Folder",
            Filter = "Folder|*.folder",
            CheckFileExists = false,
            CheckPathExists = true
        };

        if (dialog.ShowDialog() == true)
        {
            OutputFolder = Path.GetDirectoryName(dialog.FileName) ?? OutputFolder;
        }
    }

    [RelayCommand(CanExecute = nameof(CanStartDiscovery))]
    private async Task StartDiscoveryAsync()
    {
        IsRunning = true;
        IsCompleted = false;
        LogMessages.Clear();
        ProgressPercentage = 0;

        try
        {
            // Validate inputs
            if (string.IsNullOrWhiteSpace(ClientId) || string.IsNullOrWhiteSpace(TenantId))
            {
                MessageBox.Show("Please provide Client ID and Tenant ID", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (IsAppOnly && string.IsNullOrWhiteSpace(ClientSecret))
            {
                MessageBox.Show("Please provide Client Secret for App-Only authentication", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            var selectedWorkloads = Workloads.Where(w => w.IsSelected).ToList();
            if (!selectedWorkloads.Any())
            {
                MessageBox.Show("Please select at least one workload to collect", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            AddLog("🚀 Starting M365 Discovery...");

            // Create auth config
            var authConfig = IsAppOnly
                ? AuthConfig.CreateAppOnly(ClientId, TenantId, ClientSecret)
                : AuthConfig.CreateDelegated(ClientId, TenantId);

            AddLog($"🔐 Auth Mode: {authConfig.Mode}");

            // Create discovery context
            var runName = $"Discovery_{DateTime.UtcNow:yyyyMMdd_HHmmss}";
            var runOutputFolder = Path.Combine(OutputFolder, runName);
            var context = new DiscoveryContext(runOutputFolder, runName);

            AddLog($"📂 Output: {runOutputFolder}");

            // Authenticate
            StatusMessage = "Authenticating...";
            CurrentActivity = "Connecting to Microsoft Graph...";
            
            var factory = new GraphClientFactory(authConfig);
            var (graphClient, tokenInfo) = await factory.CreateAuthenticatedClientAsync();
            var resilientClient = new ResilientGraphClient(graphClient, maxParallelRequests: 4);

            AddLog($"✅ Authenticated as: {tokenInfo.Username}");
            if (!string.IsNullOrWhiteSpace(tokenInfo.AuthenticationPath))
            {
                AddLog($"🔐 Auth path: {tokenInfo.AuthenticationPath}");
            }
            AddLog($"🔍 Token expires: {tokenInfo.ExpiresOn:yyyy-MM-dd HH:mm:ss} UTC");

            // Run preflight
            StatusMessage = "Running preflight checks...";
            CurrentActivity = "Detecting permissions...";
            
            var preflightService = new PreflightService(resilientClient);
            var preflightReport = await preflightService.RunPreflightAsync(tokenInfo);

            AddLog($"✅ {preflightReport.OrganizationTestMessage}");
            AddLog($"📊 Granted permissions: {tokenInfo.GrantedScopes.Length}");

            // Display capability matrix
            foreach (var (capability, status) in preflightReport.CapabilityMatrix.Capabilities)
            {
                var icon = status switch
                {
                    CapabilityStatus.Available => "✅",
                    CapabilityStatus.Partial => "⚠",
                    CapabilityStatus.Blocked => "❌",
                    _ => "?"
                };
                AddLog($"  {icon} {capability}: {status}");
            }

            // Initialize output manager
            var outputManager = new Collector.Core.Output.OutputManager(context, preflightReport);

            // Run selected collectors
            var totalCollectors = selectedWorkloads.Count;
            var completedCollectors = 0;

            foreach (var workload in selectedWorkloads)
            {
                workload.IsRunning = true;
                workload.Status = "Running...";
                StatusMessage = $"Collecting {workload.DisplayName}...";
                CurrentActivity = workload.Description;

                AddLog($"\n▶ {workload.DisplayName}");

                try
                {
                    // Create collector instance
                    var collector = (IWorkloadCollector)Activator.CreateInstance(workload.CollectorType, resilientClient)!;
                    
                    var progress = new Progress<string>(msg =>
                    {
                        Application.Current.Dispatcher.Invoke(() => AddLog($"  {msg}"));
                    });

                    var result = await collector.CollectAsync(context, progress);
                    outputManager.AddResult(result);

                    workload.ItemsCollected = result.ItemCount;
                    workload.Status = result.Success ? $"✅ {result.ItemCount} items" : "❌ Failed";
                    workload.IsRunning = false;

                    var statusIcon = result.Success ? "✅" : "❌";
                    AddLog($"  {statusIcon} {result.Message}");
                }
                catch (Exception ex)
                {
                    workload.Status = "❌ Error";
                    workload.IsRunning = false;
                    AddLog($"  ❌ Error: {ex.Message}");
                }

                completedCollectors++;
                ProgressPercentage = (int)((completedCollectors / (double)totalCollectors) * 100);
            }

            // Finalize outputs
            StatusMessage = "Generating output files...";
            CurrentActivity = "Writing CSV and JSON files...";
            AddLog("\n📝 Generating output files...");
            
            await outputManager.FinalizeAsync();

            AddLog($"\n✅ Discovery completed successfully!");
            AddLog($"📁 Output location: {runOutputFolder}");

            StatusMessage = "Discovery completed!";
            CurrentActivity = $"Results saved to {runOutputFolder}";
            IsCompleted = true;
            ProgressPercentage = 100;

            MessageBox.Show(
                $"Discovery completed successfully!\n\nResults saved to:\n{runOutputFolder}",
                "Success",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            AddLog($"\n❌ Error: {ex.Message}");
            StatusMessage = "Discovery failed";
            CurrentActivity = ex.Message;

            MessageBox.Show(
                $"Discovery failed:\n\n{ex.Message}",
                "Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            IsRunning = false;
        }
    }

    private bool CanStartDiscovery() => !IsRunning;

    [RelayCommand]
    private void OpenOutputFolder()
    {
        if (Directory.Exists(OutputFolder))
        {
            System.Diagnostics.Process.Start("explorer.exe", OutputFolder);
        }
    }

    partial void OnIsInteractiveDelegatedChanged(bool value)
    {
        if (value) IsAppOnly = false;
    }

    partial void OnIsAppOnlyChanged(bool value)
    {
        if (value) IsInteractiveDelegated = false;
    }

    private void AddLog(string message)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            LogMessages.Add($"[{DateTime.Now:HH:mm:ss}] {message}");
        });
    }
}
