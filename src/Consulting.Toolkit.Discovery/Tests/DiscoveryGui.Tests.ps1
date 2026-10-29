[CmdletBinding()]
param([switch]$ShowMockGui)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('AdDiscoveryGuiTests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$moduleRoot=Split-Path -Parent $PSScriptRoot
$module=Import-Module (Join-Path $moduleRoot 'Consulting.Toolkit.Discovery.psd1') -Force -PassThru -WarningAction SilentlyContinue

& $module {
    param($Root,$ModuleRoot,$ShowMockGui)
    function Assert-Gui {
        param([bool]$Condition,[string]$Message)
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }
    $command=Get-Command Invoke-AdDiscoveryExport
    $specific=@($command.ScriptBlock.Ast.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $covered=@('Environment','OutputRoot','CustomerName','Server','Domain','IncludeSecurity','Credential')
    Assert-Gui (@(Compare-Object $specific $covered).Count -eq 0) 'Every discovery-specific parameter has a GUI control'
    $hasProgress=$command.Parameters.ContainsKey('ProgressAction')
    $common=@(Get-AdDiscoveryGuiCommonOptions -SupportsProgressAction $hasProgress | ForEach-Object Name)
    Assert-Gui (@(Compare-Object @($command.Parameters.Keys) @($covered+$common)).Count -eq 0) 'Every available common parameter has an advanced GUI control'

    $settings=@{Environment='Source';OutputRoot=(Join-Path $Root 'Output');CustomerName="O'Brien'; throw 'Not executable";
        Server='dc.example.test';Domain="example.test, child.example.test`nEXAMPLE.TEST; child.example.test";IncludeSecurity='True';
        EngineId='WindowsPowerShell';SchemaVersion=1;CommonParameters=@{Verbose=$true;Debug=$false;ErrorAction='Stop';OutBuffer='0';OutVariable='captured'}}
    $parameters=ConvertTo-AdDiscoveryGuiParameters $settings
    Assert-Gui ($parameters.Domain.Count -eq 2 -and $parameters.Domain[0] -eq 'example.test' -and $parameters.IncludeSecurity -eq $true) 'Domain parsing, deduplication, and switch mapping'
    Assert-Gui (-not $parameters.ContainsKey('Debug') -and $parameters.OutBuffer -eq 0) 'False switches omitted and zero buffer retained'
    $preview=Format-AdDiscoveryGuiCommand $parameters
    # Test only our generated literals against a local capture function; no AD.
    function Invoke-AdDiscoveryExport {
        [CmdletBinding()] param($Environment,$OutputRoot,$CustomerName,$Server,[string[]]$Domain,[switch]$IncludeSecurity)
        [pscustomobject]@{CustomerName=$CustomerName;Domain=$Domain;Security=[bool]$IncludeSecurity;Server=$Server}
    }
    $captured=& ([scriptblock]::Create($preview))
    Assert-Gui ($captured.CustomerName -eq $settings.CustomerName -and $captured.Domain.Count -eq 2 -and $captured.Security -eq $true) 'Command preview preserves literal quotes without executing input'
    $settingsPath=Join-Path $Root 'Settings.json'
    $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
    $loaded=Import-AdDiscoveryGuiSettings $settingsPath
    $roundtrip=ConvertTo-AdDiscoveryGuiParameters $loaded
    Assert-Gui ($roundtrip.CustomerName -eq $parameters.CustomerName -and $roundtrip.Server -eq $parameters.Server -and $roundtrip.Domain.Count -eq 2) 'Saved settings round trip'
    foreach ($bad in @(
        @{Key='OutputRoot';Value='relative\output'},@{Key='Environment';Value='..\outside'},
        @{Key='CommonParameters';Value=@{OutBuffer='-1'}},@{Key='CommonParameters';Value=@{Unexpected='value'}},
        @{Key='CommonParameters';Value=@{ProgressAction='Continue'}}
    )) {
        $candidate=$settings.Clone(); $candidate[$bad.Key]=$bad.Value
        $failed=$false
        try { ConvertTo-AdDiscoveryGuiParameters $candidate -SupportsProgressAction $false | Out-Null } catch { $failed=$true }
        Assert-Gui $failed "Invalid GUI value rejected: $($bad.Key)"
    }
    $model=New-AdDiscoveryGuiWindow (Join-Path $ModuleRoot 'Consulting.Toolkit.Discovery.psd1')
    Assert-Gui ($model.Controls.Count -ge 35 -and -not $model.Run -and -not $model.Controls.StopButton.IsEnabled) 'Window constructs without starting discovery'
    Set-AdDiscoveryGuiSettings $model $loaded
    Update-AdDiscoveryGuiPreview $model
    Assert-Gui ($model.Controls.CommandPreview.Text.Contains("O''Brien") -and $model.Controls.SecurityInput.IsChecked) 'Window reflects imported options in preview'
    Assert-Gui ($model.CommonControls.Count -eq 11) 'Windows PowerShell default exposes every available common parameter'
    $model.Window.Close()
    Write-Host 'PASS: all discovery/common options, literal command preview, saved settings, validation, and idle window construction'

    $fakeRoot=Join-Path $Root 'MockModule'
    New-Item -ItemType Directory -Path (Join-Path $fakeRoot 'Gui') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ModuleRoot 'Gui\Invoke-DiscoveryGuiWorker.ps1') -Destination (Join-Path $fakeRoot 'Gui')
    Copy-Item -LiteralPath (Join-Path $ModuleRoot 'Gui\DiscoveryGuiJob.cs') -Destination (Join-Path $fakeRoot 'Gui')
    Copy-Item -LiteralPath (Join-Path $ModuleRoot 'Gui\Initialize-DiscoveryGuiEnvironment.ps1') -Destination (Join-Path $fakeRoot 'Gui')
    $fakeModule=@'
function Invoke-AdDiscoveryExport {
    [CmdletBinding()]
    param([string]$Environment,[string]$OutputRoot,[string]$CustomerName,[string]$Server,[string[]]$Domain,[switch]$IncludeSecurity)
    Write-Host 'Mock collector started'
    Write-Warning 'Mock warning remains visible'
    if ($CustomerName -eq 'Fail') { throw 'Simulated discovery failure' }
    if ($CustomerName -eq 'Wait') {
        $child=Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"' -WindowStyle Hidden -PassThru
        Write-Host ('Owned child process: ' + $child.Id)
        Write-Host 'Waiting for cancellation'
        Start-Sleep -Seconds 30
    }
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    $partial=$CustomerName -eq 'Partial'
    [pscustomobject]@{
        Status=if($partial){'Partial'}else{'Complete'};RunRoot=$OutputRoot;DomainCount=@($Domain).Count;UserCount=1234;ComputerCount=456;GroupCount=78
        LogPath='';ExecutionStatusPath='';FailedOperationCount=if($partial){1}else{0};LoggingFailed=$false
        FailedOperations=if($partial){@([pscustomobject]@{Operation='Mock failure';Status='FAIL';Message='Simulated partial coverage'})}else{@()}
        IncompleteOperations=@();ReceivedCustomer=$CustomerName;ReceivedServer=$Server;ReceivedDomain=$Domain;ReceivedSecurity=[bool]$IncludeSecurity
    }
}
Export-ModuleMember Invoke-AdDiscoveryExport
'@
    Set-Content -LiteralPath (Join-Path $fakeRoot 'Mock.psm1') -Value $fakeModule -Encoding UTF8
    $fakeManifest=Join-Path $fakeRoot 'Mock.psd1'
    Set-Content -LiteralPath $fakeManifest -Value "@{RootModule='Mock.psm1';ModuleVersion='1.0';FunctionsToExport=@('Invoke-AdDiscoveryExport')}" -Encoding UTF8
    if ($ShowMockGui) {
        $demo=New-AdDiscoveryGuiWindow (Join-Path $ModuleRoot 'Consulting.Toolkit.Discovery.psd1')
        $demo.ManifestPath=$fakeManifest
        $demo.Window.Title='Discovery GUI - mock verification (no AD queries)'
        $demo.Controls.OutputInput.Text=Join-Path $Root 'InteractiveOutput'
        $demo.Controls.CustomerInput.Text='Partial'
        $demo.Controls.DomainsInput.Text='example.test'
        $demo.Controls.AccountText.Text='MOCK COLLECTOR - no Active Directory queries'
        $demo.Controls.ElapsedText.Text='Customer name selects scenario: Complete, Partial, Fail, or Wait.'
        Update-AdDiscoveryGuiPreview $demo
        try { $demo.Window.ShowDialog() | Out-Null } finally { $demo.Timer.Stop(); if ($demo.Run) { Close-AdDiscoveryGuiProcess $demo.Run } }
        return
    }
    foreach ($engine in @(Get-AdDiscoveryGuiEngines)) {
        foreach ($case in @('Complete','Partial','Fail','Wait')) {
            $run=$null
            try {
                $args=@{Environment='Source';OutputRoot=(Join-Path $Root ($engine.Id+$case));CustomerName=$case;Server='dc.example.test';Domain=@('example.test','child.example.test');IncludeSecurity=$true;Verbose=$true}
                if ($case -eq 'Complete') { $args.CustomerName="Literal'; throw 'Never executed" }
                $run=Start-AdDiscoveryGuiProcess $engine $args $fakeManifest
                $timer=[Diagnostics.Stopwatch]::StartNew(); $text=''
                while (-not $run.Process.HasExited -and $timer.Elapsed.TotalSeconds -lt 20) {
                    $text+=@(Read-AdDiscoveryGuiOutput $run) -join ''
                    if ($case -eq 'Wait' -and $text.Contains('Waiting for cancellation')) { Stop-AdDiscoveryGuiProcess $run }
                    Start-Sleep -Milliseconds 50
                }
                Assert-Gui $run.Process.HasExited "$($engine.Name) $case worker terminates"
                $text+=@(Read-AdDiscoveryGuiOutput $run) -join ''
                Assert-Gui ($text.Contains('Mock collector started') -and $text.Contains('Mock warning remains visible')) 'Worker streams are captured'
                if ($case -eq 'Wait') {
                    Assert-Gui ($run.Stopped -and -not (Test-Path -LiteralPath $run.ResultPath)) 'Cancellation cannot appear as successful discovery'
                    Assert-Gui ($text -match 'Owned child process: (\d+)') 'Mock runner created its owned child'
                    $childId=[int]$Matches[1]
                    $child=Get-Process -Id $childId -ErrorAction SilentlyContinue
                    Assert-Gui (-not $child -or $child.HasExited) 'Closing the job terminates the owned descendant as well as the runner'
                } else {
                    $envelope=Import-Clixml -LiteralPath $run.ResultPath
                    $expectedState=if($case -eq 'Fail'){'Failed'}else{$case}
                    Assert-Gui ($envelope.State -eq $expectedState -and $envelope.LaunchId -eq $run.LaunchId) 'Worker result has the correct state and launch identity'
                    if ($case -eq 'Fail') { Assert-Gui ($envelope.ErrorMessage.Contains('Simulated discovery failure') -and $run.Process.ExitCode -eq 1) 'Fatal error is explicit' }
                    else {
                        Assert-Gui ($envelope.Result.ReceivedCustomer -eq $args.CustomerName -and $envelope.Result.ReceivedDomain.Count -eq 2 -and $envelope.Result.ReceivedSecurity) 'Worker receives literal values, arrays, and switches'
                        Assert-Gui ($run.Process.ExitCode -eq $(if($case -eq 'Partial'){2}else{0})) 'Complete and partial have distinct exit codes'
                    }
                }
                $view=New-AdDiscoveryGuiWindow (Join-Path $ModuleRoot 'Consulting.Toolkit.Discovery.psd1')
                $view.Run=$run
                Update-AdDiscoveryGuiRun $view
                $expectedView=if($case -eq 'Wait'){'Stopped'}elseif($case -eq 'Fail'){'Failed'}else{$case}
                Assert-Gui ($view.Controls.StateText.Text -eq $expectedView -and -not $view.Run -and $view.Controls.StartButton.IsEnabled -and -not $view.Controls.StopButton.IsEnabled) 'UI final state and controls match the worker result'
                if ($case -eq 'Partial') { Assert-Gui (@($view.Controls.IssuesGrid.ItemsSource).Count -eq 1) 'Partial result exposes its failed operation in the GUI' }
                $view.Window.Close()
                Write-Host "PASS: $($engine.Name) GUI worker $case, output capture, parameter transfer, and process ownership"
            } finally { if ($run) { Close-AdDiscoveryGuiProcess $run } }
        }
    }
    Write-Host "GUI test outputs: $Root"
} $root $moduleRoot ([bool]$ShowMockGui)
