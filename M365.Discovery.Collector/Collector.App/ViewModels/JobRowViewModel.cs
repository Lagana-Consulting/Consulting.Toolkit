using Collector.App.Helpers;

namespace Collector.App.ViewModels;

public sealed class JobRowViewModel : ObservableObject
{
    private string _status = "Queued";
    private int _current;
    private int _total;
    private string _message = "";

    public JobRowViewModel(string workload, string name)
    {
        Workload = workload;
        Name = name;
    }

    public string Workload { get; }
    public string Name { get; }

    public string Status
    {
        get => _status;
        set => SetProperty(ref _status, value);
    }

    public int Current
    {
        get => _current;
        set { if (SetProperty(ref _current, value)) RaisePropertyChanged(nameof(ProgressText)); }
    }

    public int Total
    {
        get => _total;
        set { if (SetProperty(ref _total, value)) RaisePropertyChanged(nameof(ProgressText)); }
    }

    public string ProgressText => Total <= 0 ? "" : $"{Current}/{Total}";

    public string Message
    {
        get => _message;
        set => SetProperty(ref _message, value);
    }
}
