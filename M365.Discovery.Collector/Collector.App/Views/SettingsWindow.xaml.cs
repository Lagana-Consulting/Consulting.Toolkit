using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Windows;

namespace Collector.App.Views;

public partial class SettingsWindow : Window, INotifyPropertyChanged
{
    private string _clientId = string.Empty;

    public string ClientId
    {
        get => _clientId;
        set
        {
            if (_clientId != value)
            {
                _clientId = value;
                OnPropertyChanged();
                OnPropertyChanged(nameof(IsValid));
            }
        }
    }

    public string[] RequiredPermissions { get; set; } = Array.Empty<string>();
    
    public bool IsValid => !string.IsNullOrWhiteSpace(ClientId) && 
                          ClientId.Length >= 30 && 
                          ClientId.Contains('-');

    public SettingsWindow(string[] requiredPermissions, string? existingClientId = null)
    {
        InitializeComponent();
        DataContext = this;
        
        RequiredPermissions = requiredPermissions;
        PermissionsList.ItemsSource = RequiredPermissions;
        
        if (!string.IsNullOrWhiteSpace(existingClientId))
            ClientId = existingClientId;
    }

    private void OpenAzurePortal_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "https://portal.azure.com/#view/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/~/RegisteredApps",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show($"Failed to open browser: {ex.Message}", "Error", 
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void SaveAndClose_Click(object sender, RoutedEventArgs e)
    {
        if (!IsValid)
        {
            System.Windows.MessageBox.Show(
                "Please enter a valid Client ID.\n\nIt should be a GUID (36 characters) that looks like:\n12345678-1234-1234-1234-123456789abc", 
                "Invalid Client ID", 
                MessageBoxButton.OK, 
                MessageBoxImage.Warning);
            return;
        }

        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}