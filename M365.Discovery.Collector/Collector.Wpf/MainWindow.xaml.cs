using System.Windows;
using System.Windows.Controls;
using Collector.Wpf.ViewModels;

namespace Collector.Wpf;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private void ClientSecretBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is MainViewModel viewModel)
        {
            viewModel.ClientSecret = ((PasswordBox)sender).Password;
        }
    }
}