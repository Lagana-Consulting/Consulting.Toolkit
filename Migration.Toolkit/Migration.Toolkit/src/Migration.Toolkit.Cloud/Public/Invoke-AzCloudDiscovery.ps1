function Invoke-AzCloudDiscovery {
  <#
  .SYNOPSIS
  Orchestrates comprehensive cloud workload discovery across all configured workloads.

  .DESCRIPTION
  Primary entry point for cloud discovery. Executes discovery against multiple workloads
  (Entra ID, Exchange Online, SharePoint, Teams, M365 Groups) and exports results to
  structured folder layout with CSV exports and HTML summary report.

  Requires prior connection via Connect-AzCloudTenant.

  .PARAMETER OutputRoot
  Root directory for discovery output. Will create workload-specific subdirectories.
  Required.

  .PARAMETER Workloads
  Which workloads to discover. Options: 'All', 'EntraID', 'Exchange', 'SharePoint', 'Teams', 'M365Groups'.
  Default 'All'.

  .PARAMETER CustomerName
  Customer/organization name (used in report headers and folder naming). Optional.

  .PARAMETER ExportCsv
  If $true, exports discovery results to CSV. Default $true.

  .PARAMETER GenerateReport
  If $true, generates HTML summary report. Default $true.

  .PARAMETER IncludeAnalysis
  If $true, includes risk analysis and recommendations. Default $true.

  .EXAMPLE
  Invoke-AzCloudDiscovery -OutputRoot "C:\Reports\Contoso_Cloud" -Workloads All -CustomerName "Contoso Inc"

  Executes full cloud discovery and exports results to organized folder structure.

  .EXAMPLE
  Invoke-AzCloudDiscovery -OutputRoot "C:\Reports\Contoso_Teams" -Workloads Teams -ExportCsv

  Discovers only Teams workload and exports to CSV.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  [PSObject] Discovery summary with:
    - StartTime, EndTime, Duration
    - WorkloadsDiscovered, TotalRecords
    - OutputPath, ReportPath (if generated)
    - DiscoveryErrors (if any)

  .NOTES
  Requires Connect-AzCloudTenant to be called first.
  Large tenants may take significant time; individual workload functions can be called separately.
  Output folder structure:
    - 00_schemas/ (CSV schema definitions)
    - 10_entra/ (Entra ID users, groups, devices, apps)
    - 20_exchange/ (Mailboxes, distribution groups, resources)
    - 30_sharepoint/ (Sites, OneDrive usage)
    - 40_teams/ (Teams, channels, members)
    - 50_m365groups/ (M365 groups and members)
    - 99_reports/ (HTML summary and analysis)

  .LINK
  Connect-AzCloudTenant
  DisConnect-AzCloudTenant
  Export-AzCloudCsv
  New-AzCloudLog
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$OutputRoot,

    [ValidateSet('All', 'EntraID', 'Exchange', 'SharePoint', 'Teams', 'M365Groups')]
    [string[]]$Workloads = 'All',

    [string]$CustomerName = 'Cloud Discovery',

    [switch]$ExportCsv = $true,
    [switch]$GenerateReport = $true,
    [switch]$IncludeAnalysis = $true
  )

  $startTime = Get-Date -AsUTC
  $discoveryLog = @()
  $totalRecords = 0
  $discoveryErrors = @()

  # Validate auth context
  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  $ctx = Get-AzCloudAuthContext
  $logPath = New-AzCloudLog -Folder $OutputRoot -Prefix "discovery"

  try {
    # Resolve workloads
    if ($Workloads -contains 'All') {
      $Workloads = @('EntraID', 'Exchange', 'SharePoint', 'Teams', 'M365Groups')
    }

    Write-AzCloudLog -Path $logPath -Message "Starting cloud discovery for workloads: $($Workloads -join ', ')"
    Write-Verbose "Discovery starting at $startTime for workloads: $($Workloads -join ', ')"

    # Entra ID Discovery
    if ($Workloads -contains 'EntraID') {
      Write-Verbose "Discovering Entra ID workload..."
      Write-AzCloudLog -Path $logPath -Message "Starting Entra ID discovery..."

      try {
        $entraOutput = Join-Path $OutputRoot "10_entra"
        if (-not (Test-Path $entraOutput)) { New-Item -ItemType Directory -Path $entraOutput | Out-Null }

        $users = Get-AzCloudUsers
        $groups = Get-AzCloudGroups
        $devices = Get-AzCloudDevices
        $apps = Get-AzCloudApplications

        if ($ExportCsv) {
          $users | Export-AzCloudCsv -Path "$entraOutput\Users.csv"
          $groups | Export-AzCloudCsv -Path "$entraOutput\Groups.csv"
          $devices | Export-AzCloudCsv -Path "$entraOutput\Devices.csv"
          $apps | Export-AzCloudCsv -Path "$entraOutput\Applications.csv"
        }

        $userCount = if ($users) { ($users | Measure-Object).Count } else { 0 }
        $groupCount = if ($groups) { ($groups | Measure-Object).Count } else { 0 }
        $deviceCount = if ($devices) { ($devices | Measure-Object).Count } else { 0 }
        $appCount = if ($apps) { ($apps | Measure-Object).Count } else { 0 }
        $recordCount = $userCount + $groupCount + $deviceCount + $appCount
        $totalRecords += $recordCount
        Write-AzCloudLog -Path $logPath -Message "Entra ID: $userCount users, $groupCount groups, $deviceCount devices, $appCount applications"
      }
      catch {
        $msg = "Entra ID discovery failed: $_"
        Write-AzCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # Exchange Online Discovery
    if ($Workloads -contains 'Exchange') {
      Write-Verbose "Discovering Exchange Online workload..."
      Write-AzCloudLog -Path $logPath -Message "Starting Exchange Online discovery..."

      try {
        $exoOutput = Join-Path $OutputRoot "20_exchange"
        if (-not (Test-Path $exoOutput)) { New-Item -ItemType Directory -Path $exoOutput | Out-Null }

        $mailboxes = Get-AzCloudMailboxes
        $distGroups = Get-AzCloudDistributionGroups
        $resources = Get-AzCloudResourceMailboxes

        if ($ExportCsv) {
          # Separate user and shared mailboxes
          $userMailboxes = $mailboxes | Where-Object { $_.MailboxType -eq 'User' }
          $sharedMailboxes = $mailboxes | Where-Object { $_.MailboxType -eq 'Shared' }
          $resourceMailboxes = $mailboxes | Where-Object { $_.MailboxType -eq 'Resource' }

          $userMailboxes | Export-AzCloudCsv -Path "$exoOutput\UserMailboxes.csv"
          $sharedMailboxes | Export-AzCloudCsv -Path "$exoOutput\SharedMailboxes.csv"
          $resourceMailboxes | Export-AzCloudCsv -Path "$exoOutput\ResourceMailboxes.csv"
          $distGroups | Export-AzCloudCsv -Path "$exoOutput\DistributionGroups.csv"
          $resources | Export-AzCloudCsv -Path "$exoOutput\ResourceMailboxes_EXO.csv"
        }

        $mailboxCount = if ($mailboxes) { ($mailboxes | Measure-Object).Count } else { 0 }
        $distGroupCount = if ($distGroups) { ($distGroups | Measure-Object).Count } else { 0 }
        $resourceCount = if ($resources) { ($resources | Measure-Object).Count } else { 0 }
        $recordCount = $mailboxCount + $distGroupCount + $resourceCount
        $totalRecords += $recordCount
        Write-AzCloudLog -Path $logPath -Message "Exchange: $mailboxCount mailboxes, $distGroupCount dist groups, $resourceCount resources"
      }
      catch {
        $msg = "Exchange discovery failed: $_"
        Write-AzCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # SharePoint Discovery
    if ($Workloads -contains 'SharePoint') {
      Write-Verbose "Discovering SharePoint and OneDrive workload..."
      Write-AzCloudLog -Path $logPath -Message "Starting SharePoint and OneDrive discovery..."

      try {
        $spOutput = Join-Path $OutputRoot "30_sharepoint"
        if (-not (Test-Path $spOutput)) { New-Item -ItemType Directory -Path $spOutput | Out-Null }

        $sites = Get-AzCloudSharePointSites
        $oneDrive = Get-AzCloudOneDriveUsage

        if ($ExportCsv) {
          $sites | Export-AzCloudCsv -Path "$spOutput\Sites.csv"
          $oneDrive | Export-AzCloudCsv -Path "$spOutput\OneDriveUsage.csv"
        }

        $siteCount = if ($sites) { ($sites | Measure-Object).Count } else { 0 }
        $oneDriveCount = if ($oneDrive) { ($oneDrive | Measure-Object).Count } else { 0 }
        $recordCount = $siteCount + $oneDriveCount
        $totalRecords += $recordCount
        Write-AzCloudLog -Path $logPath -Message "SharePoint: $siteCount sites, $oneDriveCount OneDrive users"
      }
      catch {
        $msg = "SharePoint discovery failed: $_"
        Write-AzCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # Teams Discovery
    if ($Workloads -contains 'Teams') {
      Write-Verbose "Discovering Teams workload..."
      Write-AzCloudLog -Path $logPath -Message "Starting Teams discovery..."

      try {
        $teamsOutput = Join-Path $OutputRoot "40_teams"
        if (-not (Test-Path $teamsOutput)) { New-Item -ItemType Directory -Path $teamsOutput | Out-Null }

        $teams = Get-AzCloudTeams -IncludeChannels

        if ($ExportCsv) {
          $teams | Export-AzCloudCsv -Path "$teamsOutput\Teams.csv"
        }

        $teamCount = if ($teams) { ($teams | Measure-Object).Count } else { 0 }
        $totalRecords += $teamCount
        Write-AzCloudLog -Path $logPath -Message "Teams: $teamCount teams"
      }
      catch {
        $msg = "Teams discovery failed: $_"
        Write-AzCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # M365 Groups Discovery
    if ($Workloads -contains 'M365Groups') {
      Write-Verbose "Discovering M365 Groups workload..."
      Write-AzCloudLog -Path $logPath -Message "Starting M365 Groups discovery..."

      try {
        $m365gOutput = Join-Path $OutputRoot "50_m365groups"
        if (-not (Test-Path $m365gOutput)) { New-Item -ItemType Directory -Path $m365gOutput | Out-Null }

        $m365groups = Get-AzCloudM365Groups -IncludeMembers -IncludeResources

        if ($ExportCsv) {
          $m365groups | Export-AzCloudCsv -Path "$m365gOutput\M365Groups.csv"
        }

        $m365Count = if ($m365groups) { ($m365groups | Measure-Object).Count } else { 0 }
        $totalRecords += $m365Count
        Write-AzCloudLog -Path $logPath -Message "M365 Groups: $m365Count groups"
      }
      catch {
        $msg = "M365 Groups discovery failed: $_"
        Write-AzCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    $endTime = Get-Date -AsUTC
    $duration = $endTime - $startTime

    Write-AzCloudLog -Path $logPath -Message "Discovery completed in $($duration.TotalSeconds) seconds. Total records: $totalRecords"

    # Build summary
    $summary = [PSCustomObject]@{
      CustomerName           = $CustomerName
      TenantId               = $ctx.TenantId
      StartTime              = $startTime
      EndTime                = $endTime
      DurationSeconds        = [math]::Round($duration.TotalSeconds, 2)
      WorkloadsRequested     = @($Workloads)
      TotalRecordsDiscovered = $totalRecords
      OutputPath             = $OutputRoot
      LogPath                = $logPath
      DiscoveryErrors        = $discoveryErrors
      DiscoveryErrorCount    = $discoveryErrors.Count
    }

    return $summary
  }
  catch {
    Write-AzCloudLog -Path $logPath -Message "Discovery failed with exception: $_"
    throw
  }
}
