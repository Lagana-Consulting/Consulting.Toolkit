using System.Windows.Media;
using Collector.App.Helpers;
using Collector.Core;

namespace Collector.App.ViewModels;

public sealed class WorkloadViewModel : ObservableObject
{
    public WorkloadDefinition Definition { get; }

    private bool _isSelected;
    private PreflightStatus _status = PreflightStatus.Unknown;
    private string _lastPreflightMessage = "Not checked yet.";

    public WorkloadViewModel(WorkloadDefinition definition)
    {
        Definition = definition;
        _isSelected = definition.IsDefaultSelected;
    }

    public string Key => Definition.Key;
    public string DisplayName => Definition.DisplayName;
    public string Description => Definition.Description;

    public bool IsSelected
    {
        get => _isSelected;
        set => SetProperty(ref _isSelected, value);
    }

    public PreflightStatus Status
    {
        get => _status;
        set
        {
            if (SetProperty(ref _status, value))
            {
                RaisePropertyChanged(nameof(StatusText));
                RaisePropertyChanged(nameof(StatusBrush));
            }
        }
    }

    public string StatusText => Status switch
    {
        PreflightStatus.Available => "Available",
        PreflightStatus.Partial => "Partial",
        PreflightStatus.Blocked => "Blocked",
        PreflightStatus.Unknown => "Unknown",
        _ => "Unknown"
    };

    public System.Windows.Media.Brush StatusBrush => Status switch
    {
        PreflightStatus.Available => new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x1B, 0xA7, 0x52)),
        PreflightStatus.Partial => new SolidColorBrush(System.Windows.Media.Color.FromRgb(0xD9, 0x8C, 0x10)),
        PreflightStatus.Blocked => new SolidColorBrush(System.Windows.Media.Color.FromRgb(0xC0, 0x2B, 0x2B)),
        _ => new SolidColorBrush(System.Windows.Media.Color.FromRgb(0x66, 0x66, 0x66))
    };

    public string LastPreflightMessage
    {
        get => _lastPreflightMessage;
        set => SetProperty(ref _lastPreflightMessage, value);
    }
}
