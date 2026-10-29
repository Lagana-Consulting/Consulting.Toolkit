[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Consulting.Toolkit.Discovery.psd1'
$module = Import-Module $modulePath -Force -PassThru -WarningAction SilentlyContinue
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('AdDiscoveryModuleDiagnostics-' + [guid]::NewGuid().ToString('N'))

& $module {
    param($Root)
    function Assert-Diagnostic {
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }
    $adDiscoveryLogContext = New-AdDiscoveryDiagnostics -OutputRoot $Root
    $layout = New-AdRunLayout -OutputRoot $Root -Prefix 'Smoke' -CreateLog
    Assert-Diagnostic ((Split-Path -Leaf $layout.LogsDir) -eq '90_logs') 'Standard log folder'
    Assert-Diagnostic ((Split-Path -Leaf $layout.SchemasDir) -eq '00_schemas') 'Standard schema folder'

    Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation 'Module CSV' -Status START
    $csv = Join-Path $layout.RunRoot 'sample.csv'
    [pscustomobject]@{ Name = 'Sample'; Description = "First line`nSecond line" } | Export-AdCsvSafe -Path $csv -Force | Out-Null
    Write-AdLog -Path $adDiscoveryLogContext.LogPath -Level WARN -Message 'Simulated legacy collector warning'
    Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation 'Module CSV' -Status OK
    $events = $adDiscoveryLogContext.Events
    Assert-Diagnostic (@($events | Where-Object { $_.Kind -eq 'Csv' -and $_.Status -eq 'OK' -and $_.RowCount -eq 1 }).Count -eq 1) 'Module-scoped CSV metrics use actual rows'
    Assert-Diagnostic (@($events | Where-Object { $_.Kind -eq 'Operation' -and $_.Status -eq 'PARTIAL' }).Count -eq 1) 'Legacy warnings mark collection incomplete'
    Assert-Diagnostic ((Get-AdDiscoveryOutcome -Context $adDiscoveryLogContext).Status -eq 'Partial') 'Warnings affect final status'

    function Get-ADDomain {
        [CmdletBinding()]
        param($Identity, $Server)
        if ($Server -eq 'failed.example.test') { throw 'Simulated initial DC failure' }
        [pscustomobject]@{
            DistinguishedName = 'DC=example,DC=test'; NetBIOSName = 'EXAMPLE'; DomainMode = 'Windows2016Domain'
            PDCEmulator = 'dc.example.test'; RIDMaster = 'dc.example.test'; InfrastructureMaster = 'dc.example.test'
            Forest = 'example.test'; DNSRoot = 'example.test'
        }
    }
    function Get-ADRootDSE {
        [CmdletBinding()] param($Server)
        [pscustomobject]@{ defaultNamingContext = 'DC=example,DC=test' }
    }
    $context = Get-AdAdDomainContext -DomainFqdn 'example.test' -Server 'failed.example.test' -LogPath $adDiscoveryLogContext.LogPath
    Assert-Diagnostic ($context.Server -eq 'example.test') 'Domain fallback reports the corrected target'
    Assert-Diagnostic (@($events | Where-Object { $_.Kind -eq 'Query' -and $_.Status -eq 'RETRY' -and $_.ErrorId }).Count -eq 1) 'Domain fallback preserves original error'

    # A started operation must be durable before it finishes, including after interruption.
    Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation 'Interrupted Operation' -Status START
    $diskEvents = @(Get-Content $adDiscoveryLogContext.EventsPath | ForEach-Object { $_ | ConvertFrom-Json })
    Assert-Diagnostic (@($diskEvents | Where-Object { $_.Operation -eq 'Interrupted Operation' -and $_.Status -eq 'START' }).Count -eq 1) 'Start event flushed to disk immediately'
    Set-AdDiscoveryOperationStatus -Context $adDiscoveryLogContext -Operation 'Interrupted Operation' -Status OK

    # A second context in the same module must not reuse the first run's events.
    $firstRunId = $adDiscoveryLogContext.RunId
    $adDiscoveryLogContext = New-AdDiscoveryDiagnostics -OutputRoot (Join-Path $Root 'SecondRun')
    Assert-Diagnostic ($adDiscoveryLogContext.Events.Count -eq 1 -and $adDiscoveryLogContext.RunId -ne $firstRunId) 'Run context isolation'
    $beforeFailure = $adDiscoveryLogContext.Events.Count
    $adDiscoveryLogContext.EventsPath = $Root # A directory cannot be appended as a file.
    Write-AdDiscoveryEvent -Context $adDiscoveryLogContext -Kind Run -Operation 'Logging Failure Test' -Status INFO 3>$null
    Assert-Diagnostic ($adDiscoveryLogContext.LoggingFailed) 'Logging failure is explicit'
    Assert-Diagnostic ($adDiscoveryLogContext.LoggingErrors.Count -eq 1) 'Logging error details retained'
    Assert-Diagnostic ($adDiscoveryLogContext.Events.Count -gt $beforeFailure) 'Events retained when persistence fails'
    Assert-Diagnostic ((Get-AdDiscoveryOutcome -Context $adDiscoveryLogContext).Status -eq 'Partial') 'Logging failure prevents complete status'
    Write-Host 'PASS: module scope, layouts, row counts, warnings, DC retries, interrupted operations, run isolation, logging failures'
} $root
