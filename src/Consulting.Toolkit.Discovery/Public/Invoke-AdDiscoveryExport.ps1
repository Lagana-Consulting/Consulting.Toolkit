function Invoke-AdDiscoveryExport {
    <#
    .SYNOPSIS
    Executes a pure Active Directory discovery collection run.

    .DESCRIPTION
    Performs live AD data collection using the module's internal collector and
    generates a Discovery Index file describing all collected datasets.

    Dataset failures do not prevent independent exports. Partial runs return
    Status='Partial' and FailedOperations, and write an execution status CSV.

    This command:
      • Collects AD data (no analysis)
      • Writes structured CSV output
      • Generates Discovery.Index.json

    This command does NOT:
      • Perform risk scoring
      • Compare environments
      • Generate HTML reports
      • Run duplicate detection
      • Perform migration readiness logic

    .PARAMETER Environment
    Logical label (Source, Target, Production, etc.)

    .PARAMETER OutputRoot
    Root path where discovery run folder will be created.

    .PARAMETER CustomerName
    Optional metadata stored in discovery index.

    .PARAMETER Server
    Optional initial DC for forest discovery. Per-domain collection validates
    the server's naming context and uses a target in the requested domain.
    Failed queries may retry using that domain's FQDN, never the runner's
    implicit domain. Rows outside the requested domain are rejected.

    .PARAMETER Credential
    Optional alternate account for network access to AD and Group Policy. Use
    Get-Credential to obtain a PSCredential. Discovery runs in an isolated Windows
    network logon session; local identity and local file permissions are unchanged.
    Passwords are never serialized into runner requests or passed on a command line.

    .EXAMPLE
    Invoke-AdDiscoveryExport -Environment Source -OutputRoot C:\Discovery
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Environment = 'Source',

        [Parameter()]
        [string]$OutputRoot = 'C:\Discovery',

        [Parameter()]
        [string]$CustomerName,

        [Parameter()]
        [string]$Server,

        [string[]]$Domain,

        [switch]$IncludeSecurity,

        [ValidateNotNull()]
        # Validate explicitly before conversion: the Windows PowerShell 5.1
        # PSCredential binder can prompt on null, even in noninteractive hosts.
        [object]$Credential
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($PSBoundParameters.ContainsKey('Credential')) {
        if ($Credential -isnot [System.Management.Automation.PSCredential]) {
            throw 'Credential must be a PSCredential obtained with Get-Credential.'
        }
        $credentialParameters=@{Environment=$Environment;OutputRoot=$OutputRoot}
        foreach ($name in $PSBoundParameters.Keys) {
            if ($name -ne 'Credential') { $credentialParameters[$name]=$PSBoundParameters[$name] }
        }
        return Invoke-AdDiscoveryCredentialExport -Parameters $credentialParameters -Credential $Credential `
            -ManifestPath (Join-Path $PSScriptRoot '..\Consulting.Toolkit.Discovery.psd1')
    }

    Write-Host "========================================"
    Write-Host "Consulting.Toolkit.Discovery Collector"
    Write-Host "========================================"
    Write-Host ""

    # Build parameter splat for the internal collector.
    $invokeParams = @{
        Environment  = $Environment
        OutputRoot   = $OutputRoot
        CustomerName = $CustomerName
    }

    if ($PSBoundParameters.ContainsKey('Server') -and -not [string]::IsNullOrWhiteSpace($Server)) {
        $invokeParams.Server = $Server
    }

    if ($Domain) {
        $invokeParams.Domain = $Domain
    }

    if ($IncludeSecurity) {
        $invokeParams.IncludeSecurity = $true
    }

    # Create durable startup diagnostics before any forest queries can fail.
    $module = $MyInvocation.MyCommand.Module
    $networkCredentialUser=Get-Variable -Name adDiscoveryNetworkCredentialUserName -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    $metadata = @{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PSEdition = $PSVersionTable.PSEdition
        OSVersion = [Environment]::OSVersion.VersionString
        Is64BitProcess = [Environment]::Is64BitProcess
        MachineName = [Environment]::MachineName
        RunAs = "{0}\{1}" -f [Environment]::UserDomainName, [Environment]::UserName
        AuthenticationMode = if ($networkCredentialUser) { 'AlternateNetwork' } else { 'CurrentWindows' }
        NetworkCredentialUserName = [string]$networkCredentialUser
        ModuleVersion = if ($module) { $module.Version.ToString() } else { 'DotSourced' }
        CollectorSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..\Private\Invoke-AdDiscovery.ps1') -Algorithm SHA256).Hash
        Environment = $Environment
        CustomerName = $CustomerName
        OutputRoot = $OutputRoot
        RequestedDomains = @($Domain)
        RequestedServer = $Server
        IncludeSecurity = [bool]$IncludeSecurity
    }
    $adDiscoveryLogContext = New-AdDiscoveryDiagnostics -OutputRoot $OutputRoot -Metadata $metadata
    $invokeParams.LogContext = $adDiscoveryLogContext
    $result = $null
    try {
        # Capture ALL pipeline output
        $raw = @(Invoke-AdDiscovery @invokeParams)

        # Select last object that contains RunRoot
        $result = $raw |
        Where-Object {
            $_ -and
            $_.PSObject -and
            ($_.PSObject.Properties.Name -contains 'RunRoot')
        } |
        Select-Object -Last 1

        if (-not $result) {
            $types = ($raw | ForEach-Object { $_.GetType().FullName } | Sort-Object -Unique) -join ', '
            throw "AD discovery collector did not return a result object with RunRoot. Returned types: $types"
        }

        # Generate discovery index
        $indexPath = Join-Path $result.RunRoot '99_manifest\Discovery.Index.json'

        $tags = @()
        if ($IncludeSecurity) { $tags += 'security' }

        Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation 'Discovery Index' -Status START
        New-ADDiscoveryIndex `
            -RunRoot $result.RunRoot `
            -Environment $Environment `
            -CustomerName $CustomerName `
            -OutputPath $indexPath `
            -Tags $tags
        Write-AdDiscoveryEvent -Context $adDiscoveryLogContext -Kind Artifact -Operation 'Discovery Index' -Status OK -OutputPath $indexPath -Bytes (Get-Item -LiteralPath $indexPath).Length
        Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation 'Discovery Index' -Status OK
        $outcome = Get-AdDiscoveryOutcome -Context $adDiscoveryLogContext
        Write-AdDiscoveryEvent -Context $adDiscoveryLogContext -Kind Run -Operation 'Discovery Run' -Status $outcome.Status
        $outcome = Get-AdDiscoveryOutcome -Context $adDiscoveryLogContext
        $result.Status = $outcome.Status
        $result.FailedOperations = $outcome.FailedOperations
        $result.FailedOperationCount = $outcome.FailedOperations.Count
        $result.IncompleteOperations = $outcome.IncompleteOperations
        $result.LoggingFailed = $adDiscoveryLogContext.LoggingFailed
        $result.LoggingErrors = $adDiscoveryLogContext.LoggingErrors.ToArray()

        Write-Host ""
        if ($result.Status -eq 'Partial') {
            Write-Warning "Discovery is partial: $($result.FailedOperationCount) failed operation(s), $($result.IncompleteOperations.Count) incomplete operation(s), LoggingFailed=$($result.LoggingFailed). Review the returned result and the log at '$($result.LogPath)'." -WarningAction Continue
        } else {
            Write-Host "[OK] Discovery complete" -ForegroundColor Green
        }
        Write-Host "RunRoot: $($result.RunRoot)" -ForegroundColor Yellow
        Write-Host "Index:   $indexPath" -ForegroundColor Yellow
        Write-Host "Diagnostic events: $($result.DiagnosticLogPath)" -ForegroundColor Yellow
        if ($result.ExecutionStatusPath) {
            Write-Host "Execution status: $($result.ExecutionStatusPath)" -ForegroundColor Yellow
        }
        Write-Host ""

        return $result
    } catch {
        $failure = $_
        if ($adDiscoveryLogContext.Operations.Count -gt 0) {
            $operation = $adDiscoveryLogContext.Operations[$adDiscoveryLogContext.Operations.Count - 1].Operation
            Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation $operation -Status FAIL -ErrorRecord $failure
        }
        Write-AdDiscoveryEvent -Context $adDiscoveryLogContext -Kind Run -Operation 'Discovery Run' -Status FAIL -ErrorRecord $failure
        Write-AdDiscoveryEvent -Context $adDiscoveryLogContext -Kind Run -Operation 'Loaded Modules' -Status INFO -Details @(
            Get-Module ActiveDirectory, GroupPolicy, Consulting.Toolkit.Discovery | Select-Object Name, @{ Name = 'Version'; Expression = { $_.Version.ToString() } }
        )
        $statusPath = if ($result) {
            Join-Path $result.RunRoot '99_manifest\Run__ExecutionStatus__Run.csv'
        } else {
            Join-Path (Split-Path -Parent $adDiscoveryLogContext.LogPath) ("Run__ExecutionStatus__{0}.csv" -f $adDiscoveryLogContext.RunId)
        }
        Save-AdDiscoveryExecutionStatus -Context $adDiscoveryLogContext -Path $statusPath
        Write-Warning "Discovery stopped. Log: $($adDiscoveryLogContext.LogPath); diagnostic events: $($adDiscoveryLogContext.EventsPath)" -WarningAction Continue
        throw
    }
}
