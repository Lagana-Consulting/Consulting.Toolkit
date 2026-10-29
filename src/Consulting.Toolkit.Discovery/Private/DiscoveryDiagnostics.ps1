# Run-scoped diagnostics. Collectors inherit this context through PowerShell's
# caller scope; no module-global state is retained between discovery runs.
function New-AdDiscoveryDiagnostics {
    param([string]$OutputRoot, [hashtable]$Metadata = @{})
    $root = Resolve-AdPath -Path $OutputRoot
    $folder = Join-Path $root '90_logs'
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null
    $runId = [guid]::NewGuid().ToString('N')
    $context = [pscustomobject]@{
        RunId = $runId
        LogPath = Join-Path $folder "discovery-$runId.log"
        EventsPath = Join-Path $folder "discovery-$runId.jsonl"
        ExecutionStatusPath = $null
        Domain = ''
        Server = ''
        Events = New-Object System.Collections.Generic.List[object]
        Operations = New-Object System.Collections.Generic.List[object]
        LoggingFailed = $false
        LoggingErrors = New-Object System.Collections.Generic.List[object]
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($context.LogPath, '', $utf8)
    [System.IO.File]::WriteAllText($context.EventsPath, '', $utf8)
    Write-AdDiscoveryEvent -Context $context -Kind Run -Operation 'Run Context' -Status INFO -Details $Metadata
    return $context
}

function Write-AdDiscoveryEvent {
    [CmdletBinding()]
    param(
        $Context,
        [string]$Kind = 'Collector',
        [string]$Operation,
        [string]$Status = 'INFO',
        [string]$Message = '',
        [string]$Server,
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        $Token,
        [string]$OutputPath = '',
        $RowCount = $null,
        $Bytes = $null,
        $Details = $null,
        [switch]$MarkIncomplete,
        [switch]$NoCurrentToken,
        [switch]$PassThru
    )
    if (-not $Context) {
        $Context = Get-Variable -Name adDiscoveryLogContext -ValueOnly -ErrorAction SilentlyContinue
    }
    if (-not $Context) { return }
    if (-not $Token -and -not $NoCurrentToken -and $Context.Operations.Count -gt 0) {
        $Token = $Context.Operations[$Context.Operations.Count - 1]
    }
    if (-not $Operation -and $Token) { $Operation = $Token.Operation }
    if ($Token -and $Kind -eq 'Csv' -and $Status -eq 'START') { $Token.AttemptedPaths.Add($OutputPath) }
    if ($MarkIncomplete -and $Token) { $Token.IssueCount++ }
    if (-not $Message -and $ErrorRecord) { $Message = $ErrorRecord.Exception.Message }
    $invocation = if ($ErrorRecord) { $ErrorRecord.InvocationInfo } else { $null }
    $event = [pscustomobject][ordered]@{
        Time = [datetime]::UtcNow.ToString('o')
        RunId = $Context.RunId
        Kind = $Kind
        OperationId = if ($Token) { $Token.Id } else { '' }
        Operation = $Operation
        Status = $Status
        Domain = $Context.Domain
        Server = if ($PSBoundParameters.ContainsKey('Server')) { $Server } else { $Context.Server }
        Message = $Message
        StartedUtc = if ($Token) { $Token.StartedUtc } else { $null }
        EndedUtc = if ($Token -and $Kind -eq 'Operation' -and $Status -ne 'START') { [datetime]::UtcNow.ToString('o') } else { $null }
        DurationMs = if ($Token) { [math]::Round($Token.Timer.Elapsed.TotalMilliseconds, 2) } else { $null }
        OutputPath = $OutputPath
        RowCount = $RowCount
        Bytes = $Bytes
        ExceptionType = if ($ErrorRecord) { $ErrorRecord.Exception.GetType().FullName } else { '' }
        ErrorId = if ($ErrorRecord) { $ErrorRecord.FullyQualifiedErrorId } else { '' }
        Category = if ($ErrorRecord) { [string]$ErrorRecord.CategoryInfo.Category } else { '' }
        ScriptName = if ($invocation) { $invocation.ScriptName } else { '' }
        ScriptLineNumber = if ($invocation) { $invocation.ScriptLineNumber } else { $null }
        PositionMessage = if ($invocation) { $invocation.PositionMessage } else { '' }
        ScriptStackTrace = if ($ErrorRecord) { $ErrorRecord.ScriptStackTrace } else { '' }
        Exception = if ($ErrorRecord) { $ErrorRecord.Exception.ToString() } else { '' }
        Details = if ($null -ne $Details) { ConvertTo-Json -InputObject $Details -Depth 8 -Compress } else { '' }
    }
    $Context.Events.Add($event)
    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $json = ConvertTo-Json -InputObject $event -Depth 8 -Compress
        [System.IO.File]::AppendAllText($Context.EventsPath, $json + [Environment]::NewLine, $utf8)
        $line = '{0} [{1}] {2}: {3} Domain={4} Server={5} DurationMs={6} Rows={7} Path={8}' -f
            $event.Time, $Status, $Operation, $Message, $event.Domain, $event.Server, $event.DurationMs, $RowCount, $OutputPath
        if ($ErrorRecord) {
            $line += [Environment]::NewLine + ('ErrorId={0} ExceptionType={1}{2}{3}{2}{4}{2}{5}' -f
                $event.ErrorId, $event.ExceptionType, [Environment]::NewLine, $event.PositionMessage, $event.ScriptStackTrace, $event.Exception)
        }
        if ($event.Details) { $line += [Environment]::NewLine + $event.Details }
        [System.IO.File]::AppendAllText($Context.LogPath, $line + [Environment]::NewLine, $utf8)
    } catch {
        $Context.LoggingErrors.Add([pscustomobject]@{
            Time = [datetime]::UtcNow.ToString('o'); Message = $_.Exception.Message
            ErrorId = $_.FullyQualifiedErrorId; ScriptStackTrace = $_.ScriptStackTrace
            LogPath = $Context.LogPath; EventsPath = $Context.EventsPath
        })
        if (-not $Context.LoggingFailed) {
            Write-Warning "Discovery diagnostics could not be written: $($_.Exception.Message). Events remain in memory." -WarningAction Continue
        }
        $Context.LoggingFailed = $true
    }
    if ($PassThru) { return $event }
}

function Set-AdDiscoveryOperationStatus {
    param($Context, [string]$Operation, [string]$Status, [string]$Message = '',
        [System.Management.Automation.ErrorRecord]$ErrorRecord)
    $token = $null
    if ($Status -eq 'START') {
        $token = [pscustomobject]@{
            Id = [guid]::NewGuid().ToString('N'); Operation = $Operation
            StartedUtc = [datetime]::UtcNow.ToString('o'); Timer = [System.Diagnostics.Stopwatch]::StartNew()
            IssueCount = 0; Outputs = New-Object System.Collections.Generic.List[object]
            AttemptedPaths = New-Object System.Collections.Generic.List[string]
        }
        $Context.Operations.Add($token)
    } else {
        for ($i = $Context.Operations.Count - 1; $i -ge 0; $i--) {
            if ($Context.Operations[$i].Operation -eq $Operation) {
                $token = $Context.Operations[$i]
                $Context.Operations.RemoveAt($i)
                break
            }
        }
        if ($token) {
            $token.Timer.Stop()
            if ($Status -eq 'OK' -and $token.IssueCount -gt 0) { $Status = 'PARTIAL' }
            if ($Status -eq 'OK' -and $token.Outputs.Count -gt 0 -and
                @($token.Outputs | Where-Object { $_.RowCount -gt 0 }).Count -eq 0) { $Status = 'EMPTY' }
        }
        if ($Status -in @('FAIL', 'PARTIAL', 'SKIP') -and $Context.Operations.Count -gt 0) {
            $Context.Operations[$Context.Operations.Count - 1].IssueCount++
        }
    }
    $paths = ''; $rows = $null; $bytes = $null
    if ($token -and $token.Outputs.Count -gt 0) {
        $paths = ($token.Outputs | ForEach-Object { $_.Path }) -join '; '
        $rows = ($token.Outputs | Measure-Object -Property RowCount -Sum).Sum
        $bytes = ($token.Outputs | Measure-Object -Property Bytes -Sum).Sum
    }
    if ($token -and $token.AttemptedPaths.Count -gt 0) { $paths = $token.AttemptedPaths -join '; ' }
    Write-AdDiscoveryEvent -Context $Context -Kind Operation -Operation $Operation -Status $Status -Message $Message `
        -Token $token -NoCurrentToken -ErrorRecord $ErrorRecord -OutputPath $paths -RowCount $rows -Bytes $bytes
}

function Write-AdDiscoveryCsvResult {
    param([string]$Path, [int]$RowCount)
    $context = Get-Variable -Name adDiscoveryLogContext -ValueOnly -ErrorAction SilentlyContinue
    if (-not $context) { return }
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($context.Operations.Count -gt 0) {
        $context.Operations[$context.Operations.Count - 1].Outputs.Add([pscustomobject]@{
            Path = $file.FullName; RowCount = $RowCount; Bytes = $file.Length
        })
    }
    $status = if ($RowCount -eq 0) { 'EMPTY' } else { 'OK' }
    Write-AdDiscoveryEvent -Context $context -Kind Csv -Status $status -OutputPath $file.FullName -RowCount $RowCount -Bytes $file.Length
}

function Save-AdDiscoveryExecutionStatus {
    param($Context, [string]$Path)
    try {
        $Context.Events.ToArray() | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 -Force -ErrorAction Stop
        $Context.ExecutionStatusPath = $Path
    } catch {
        $Context.ExecutionStatusPath = $null
        Write-AdDiscoveryEvent -Context $Context -Kind Operation -Operation 'Execution Status Export' -Status FAIL -ErrorRecord $_
    }
}

function Get-AdDiscoveryOutcome {
    param($Context)
    $failed = @($Context.Events | Where-Object { $_.Kind -eq 'Operation' -and $_.Status -eq 'FAIL' })
    $incomplete = @($Context.Events | Where-Object {
        ($_.Kind -eq 'Operation' -and $_.Status -in @('PARTIAL', 'SKIP')) -or
        ($_.Kind -eq 'Collector' -and $_.Status -eq 'PARTIAL' -and -not $_.OperationId)
    })
    [pscustomobject]@{
        Status = if ($failed.Count -or $incomplete.Count -or $Context.LoggingFailed) { 'Partial' } else { 'Complete' }
        FailedOperations = $failed
        IncompleteOperations = $incomplete
    }
}

function Stop-AdDiscoveryCollection {
    param([string]$Message, [ValidateSet('SKIP', 'FAIL')][string]$Status = 'SKIP')
    $exception = New-Object System.InvalidOperationException($Message)
    $exception.Data['DiscoveryStatus'] = $Status
    throw $exception
}

function Invoke-AdDiscoveryQuery {
    [CmdletBinding()]
    param(
        [string]$Operation,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Server,
        [string]$DomainFqdn,
        [string]$ExpectedDomainDn,
        [scriptblock]$Query,
        [switch]$RetryInDomain
    )
    Write-AdDiscoveryEvent -Kind Query -Operation $Operation -Status START -Server $Server -Details @{ Attempt = 1; RequestedServer = $Server }
    try {
        $rows = @(& $Query $Server)
        Assert-AdDiscoveryDomainRows -Rows $rows -ExpectedDomainDn $ExpectedDomainDn
        Write-AdDiscoveryEvent -Kind Query -Operation $Operation -Status OK -Server $Server -RowCount $rows.Count -Details @{ Attempt = 1; RequestedServer = $Server }
        return $rows
    } catch {
        if (-not $RetryInDomain -or [string]::IsNullOrWhiteSpace($DomainFqdn) -or $Server -eq $DomainFqdn -or $_.Exception.Data['DiscoveryTargetMismatch']) { throw }
        Write-AdDiscoveryEvent -Kind Query -Operation $Operation -Status RETRY -Server $Server -ErrorRecord $_ `
            -Details @{ Attempt = 1; RequestedServer = $Server; NextTarget = $DomainFqdn }
    }
    try {
        # A domain FQDN lets AD locate a DC within that domain. Never remove
        # -Server and fall back to the runner's current domain or AD: drive.
        $rows = @(& $Query $DomainFqdn)
        Assert-AdDiscoveryDomainRows -Rows $rows -ExpectedDomainDn $ExpectedDomainDn
        Write-AdDiscoveryEvent -Kind Query -Operation $Operation -Status OK -Server $DomainFqdn -RowCount $rows.Count `
            -Details @{ Attempt = 2; RequestedServer = $Server; Target = $DomainFqdn }
        return $rows
    } catch {
        # Preserve the second query's ErrorRecord; the first is already durable.
        Write-AdDiscoveryEvent -Kind Query -Operation $Operation -Status ERROR -Server $DomainFqdn -ErrorRecord $_ -Details @{ Attempt = 2; Target = $DomainFqdn }
        throw
    }
}
