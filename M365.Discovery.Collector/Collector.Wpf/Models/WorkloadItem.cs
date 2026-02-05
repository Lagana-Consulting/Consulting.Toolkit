using CommunityToolkit.Mvvm.ComponentModel;

namespace Collector.Wpf.Models;

public partial class WorkloadItem : ObservableObject
{
    [ObservableProperty]
    private bool _isSelected;

    [ObservableProperty]
    private string _displayName = string.Empty;

    [ObservableProperty]
    private string _description = string.Empty;

    [ObservableProperty]
    private string _workloadKey = string.Empty;

    [ObservableProperty]
    private string _category = string.Empty;

    [ObservableProperty]
    private string _status = "Not Started";

    [ObservableProperty]
    private int _itemsCollected;

    [ObservableProperty]
    private bool _isRunning;

    public Type CollectorType { get; set; } = null!;

    public static List<WorkloadItem> GetAvailableWorkloads()
    {
        return new List<WorkloadItem>
        {
            // Entra ID Directory
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Entra Users",
                Description = "User accounts with license assignments",
                WorkloadKey = "entra.users",
                Category = "Entra ID",
                CollectorType = typeof(Collector.Core.Collectors.EntraUsersCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Entra Groups",
                Description = "Security and distribution groups",
                WorkloadKey = "entra.groups",
                Category = "Entra ID",
                CollectorType = typeof(Collector.Core.Collectors.EntraGroupsCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "M365 Groups",
                Description = "Microsoft 365 Groups and Teams",
                WorkloadKey = "entra.m365groups",
                Category = "Entra ID",
                CollectorType = typeof(Collector.Core.Collectors.M365GroupsCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Applications",
                Description = "App registrations",
                WorkloadKey = "entra.apps",
                Category = "Entra ID",
                CollectorType = typeof(Collector.Core.Collectors.EntraApplicationsCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Service Principals",
                Description = "Enterprise applications",
                WorkloadKey = "entra.servicePrincipals",
                Category = "Entra ID",
                CollectorType = typeof(Collector.Core.Collectors.EntraServicePrincipalsCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Directory Roles",
                Description = "Role assignments and members",
                WorkloadKey = "entra.roles",
                Category = "Entra ID",
                CollectorType = typeof(Collector.Core.Collectors.EntraRolesCollector)
            },

            // Organization
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Organization Settings",
                Description = "Tenant details, domains, licenses",
                WorkloadKey = "organization.basic",
                Category = "Organization",
                CollectorType = typeof(Collector.Core.Collectors.OrganizationCollector)
            },

            // Usage Reports
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "OneDrive Usage",
                Description = "Storage and activity metrics",
                WorkloadKey = "reports.onedrive",
                Category = "Usage Reports",
                CollectorType = typeof(Collector.Core.Collectors.OneDriveUsageCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "SharePoint Usage",
                Description = "Site usage and storage",
                WorkloadKey = "reports.sharepoint",
                Category = "Usage Reports",
                CollectorType = typeof(Collector.Core.Collectors.SharePointUsageCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Teams Activity",
                Description = "User activity and usage",
                WorkloadKey = "reports.teams",
                Category = "Usage Reports",
                CollectorType = typeof(Collector.Core.Collectors.TeamsActivityCollector)
            },
            new WorkloadItem
            {
                IsSelected = true,
                DisplayName = "Exchange Mailbox Usage",
                Description = "Mailbox size and quota",
                WorkloadKey = "reports.exchange",
                Category = "Usage Reports",
                CollectorType = typeof(Collector.Core.Collectors.ExchangeMailboxUsageCollector)
            },
        };
    }
}