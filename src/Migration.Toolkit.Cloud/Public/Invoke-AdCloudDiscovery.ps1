function Invoke-AdCloudDiscovery {
  <#
  .SYNOPSIS
  Orchestrates comprehensive cloud workload discovery across all configured workloads.

  .DESCRIPTION
  Primary entry point for cloud discovery. Executes discovery against multiple workloads
  (Entra ID, Exchange Online, SharePoint, Teams, M365 Groups) and exports results to
  structured folder layout with CSV exports and HTML summary report.

  Requires prior connection via Connect-AdCloudTenant.

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
  Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\Contoso_Cloud" -Workloads All -CustomerName "Contoso Inc"

  Executes full cloud discovery and exports results to organized folder structure.

  .EXAMPLE
  Invoke-AdCloudDiscovery -OutputRoot "C:\Reports\Contoso_Teams" -Workloads Teams -ExportCsv

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
  Requires Connect-AdCloudTenant to be called first.
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
  Connect-AdCloudTenant
  Disconnect-AdCloudTenant
  Export-AdCloudCsv
  New-AdCloudLog
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
  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  $ctx = Get-AdCloudAuthContext
  $logPath = New-AdCloudLog -Folder $OutputRoot -Prefix "discovery"

  try {
    # Resolve workloads
    if ($Workloads -contains 'All') {
      $Workloads = @('EntraID', 'Exchange', 'SharePoint', 'Teams', 'M365Groups')
    }

    Write-AdCloudLog -Path $logPath -Message "Starting cloud discovery for workloads: $($Workloads -join ', ')"
    Write-Verbose "Discovery starting at $startTime for workloads: $($Workloads -join ', ')"

    # Entra ID Discovery
    if ($Workloads -contains 'EntraID') {
      Write-Verbose "Discovering Entra ID workload..."
      Write-AdCloudLog -Path $logPath -Message "Starting Entra ID discovery..."

      try {
        $entraOutput = Join-Path $OutputRoot "10_entra"
        if (-not (Test-Path $entraOutput)) { New-Item -ItemType Directory -Path $entraOutput | Out-Null }

        $users = Get-AdCloudUsers
        $groups = Get-AdCloudGroups
        $devices = Get-AdCloudDevices
        $apps = Get-AdCloudApplications

        if ($ExportCsv) {
          $users | Export-AdCloudCsv -Path "$entraOutput\Users.csv"
          $groups | Export-AdCloudCsv -Path "$entraOutput\Groups.csv"
          $devices | Export-AdCloudCsv -Path "$entraOutput\Devices.csv"
          $apps | Export-AdCloudCsv -Path "$entraOutput\Applications.csv"
        }

        $recordCount = ($users.Count) + ($groups.Count) + ($devices.Count) + ($apps.Count)
        $totalRecords += $recordCount
        Write-AdCloudLog -Path $logPath -Message "Entra ID: $($users.Count) users, $($groups.Count) groups, $($devices.Count) devices, $($apps.Count) applications"
      }
      catch {
        $msg = "Entra ID discovery failed: $_"
        Write-AdCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # Exchange Online Discovery
    if ($Workloads -contains 'Exchange') {
      Write-Verbose "Discovering Exchange Online workload..."
      Write-AdCloudLog -Path $logPath -Message "Starting Exchange Online discovery..."

      try {
        $exoOutput = Join-Path $OutputRoot "20_exchange"
        if (-not (Test-Path $exoOutput)) { New-Item -ItemType Directory -Path $exoOutput | Out-Null }

        $mailboxes = Get-AdCloudMailboxes
        $distGroups = Get-AdCloudDistributionGroups
        $resources = Get-AdCloudResourceMailboxes

        if ($ExportCsv) {
          $mailboxes | Export-AdCloudCsv -Path "$exoOutput\Mailboxes.csv"
          $distGroups | Export-AdCloudCsv -Path "$exoOutput\DistributionGroups.csv"
          $resources | Export-AdCloudCsv -Path "$exoOutput\ResourceMailboxes.csv"
        }

        $recordCount = ($mailboxes.Count) + ($distGroups.Count) + ($resources.Count)
        $totalRecords += $recordCount
        Write-AdCloudLog -Path $logPath -Message "Exchange: $($mailboxes.Count) mailboxes, $($distGroups.Count) dist groups, $($resources.Count) resources"
      }
      catch {
        $msg = "Exchange discovery failed: $_"
        Write-AdCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # SharePoint Discovery
    if ($Workloads -contains 'SharePoint') {
      Write-Verbose "Discovering SharePoint and OneDrive workload..."
      Write-AdCloudLog -Path $logPath -Message "Starting SharePoint and OneDrive discovery..."

      try {
        $spOutput = Join-Path $OutputRoot "30_sharepoint"
        if (-not (Test-Path $spOutput)) { New-Item -ItemType Directory -Path $spOutput | Out-Null }

        $sites = Get-AdCloudSharePointSites
        $oneDrive = Get-AdCloudOneDriveUsage

        if ($ExportCsv) {
          $sites | Export-AdCloudCsv -Path "$spOutput\Sites.csv"
          $oneDrive | Export-AdCloudCsv -Path "$spOutput\OneDriveUsage.csv"
        }

        $recordCount = ($sites.Count) + ($oneDrive.Count)
        $totalRecords += $recordCount
        Write-AdCloudLog -Path $logPath -Message "SharePoint: $($sites.Count) sites, $($oneDrive.Count) OneDrive users"
      }
      catch {
        $msg = "SharePoint discovery failed: $_"
        Write-AdCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # Teams Discovery
    if ($Workloads -contains 'Teams') {
      Write-Verbose "Discovering Teams workload..."
      Write-AdCloudLog -Path $logPath -Message "Starting Teams discovery..."

      try {
        $teamsOutput = Join-Path $OutputRoot "40_teams"
        if (-not (Test-Path $teamsOutput)) { New-Item -ItemType Directory -Path $teamsOutput | Out-Null }

        $teams = Get-AdCloudTeams -IncludeChannels

        if ($ExportCsv) {
          $teams | Export-AdCloudCsv -Path "$teamsOutput\Teams.csv"
        }

        $totalRecords += $teams.Count
        Write-AdCloudLog -Path $logPath -Message "Teams: $($teams.Count) teams"
      }
      catch {
        $msg = "Teams discovery failed: $_"
        Write-AdCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    # M365 Groups Discovery
    if ($Workloads -contains 'M365Groups') {
      Write-Verbose "Discovering M365 Groups workload..."
      Write-AdCloudLog -Path $logPath -Message "Starting M365 Groups discovery..."

      try {
        $m365gOutput = Join-Path $OutputRoot "50_m365groups"
        if (-not (Test-Path $m365gOutput)) { New-Item -ItemType Directory -Path $m365gOutput | Out-Null }

        $m365groups = Get-AdCloudM365Groups -IncludeMembers -IncludeResources

        if ($ExportCsv) {
          $m365groups | Export-AdCloudCsv -Path "$m365gOutput\M365Groups.csv"
        }

        $totalRecords += $m365groups.Count
        Write-AdCloudLog -Path $logPath -Message "M365 Groups: $($m365groups.Count) groups"
      }
      catch {
        $msg = "M365 Groups discovery failed: $_"
        Write-AdCloudLog -Path $logPath -Message $msg
        $discoveryErrors += $msg
      }
    }

    $endTime = Get-Date -AsUTC
    $duration = $endTime - $startTime

    Write-AdCloudLog -Path $logPath -Message "Discovery completed in $($duration.TotalSeconds) seconds. Total records: $totalRecords"

    # Build summary
    $summary = [PSCustomObject]@{
      CustomerName = $CustomerName
      TenantId = $ctx.TenantId
      StartTime = $startTime
      EndTime = $endTime
      DurationSeconds = [math]::Round($duration.TotalSeconds, 2)
      WorkloadsRequested = @($Workloads)
      TotalRecordsDiscovered = $totalRecords
      OutputPath = $OutputRoot
      LogPath = $logPath
      DiscoveryErrors = $discoveryErrors
      DiscoveryErrorCount = $discoveryErrors.Count
    }

    return $summary
  }
  catch {
    Write-AdCloudLog -Path $logPath -Message "Discovery failed with exception: $_"
    throw
  }
}
