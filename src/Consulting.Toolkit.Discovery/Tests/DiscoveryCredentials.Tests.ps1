# Synthetic credentials are used only with a local fake collector. No AD binds.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('AdDiscoveryCredentialTests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'Gui') -Force | Out-Null
$moduleRoot=Split-Path -Parent $PSScriptRoot
$module=Import-Module (Join-Path $moduleRoot 'Consulting.Toolkit.Discovery.psd1') -Force -PassThru -WarningAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $moduleRoot 'Gui\DiscoveryGuiJob.cs'),(Join-Path $moduleRoot 'Gui\Invoke-DiscoveryGuiWorker.ps1'),(Join-Path $moduleRoot 'Gui\Initialize-DiscoveryGuiEnvironment.ps1') -Destination (Join-Path $root 'Gui')
$tokenSource=@'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
namespace DiscoveryCredentialTests {
 public static class TokenInspector {
  [StructLayout(LayoutKind.Sequential)] private struct Luid { public uint Low; public int High; }
  [StructLayout(LayoutKind.Sequential)] private struct Statistics {
   public Luid Token, Authentication; public long Expiration; public int Type, Level;
   public uint Charged, Available, Groups, Privileges; public Luid Modified;
  }
  [DllImport("advapi32.dll",SetLastError=true)] private static extern bool GetTokenInformation(IntPtr token,int type,out Statistics data,int size,out int needed);
  public static string AuthenticationId() {
   using(var identity=WindowsIdentity.GetCurrent()) {
    Statistics data; int needed;
    if(!GetTokenInformation(identity.Token,10,out data,Marshal.SizeOf(typeof(Statistics)),out needed)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    return data.Authentication.High.ToString("X8")+data.Authentication.Low.ToString("X8");
   }
  }
 }
}
'@
[IO.File]::WriteAllText((Join-Path $root 'TokenInspector.cs'),$tokenSource)
Add-Type -Path (Join-Path $root 'TokenInspector.cs')
$fake=@'
Add-Type -Path (Join-Path $PSScriptRoot 'TokenInspector.cs')
function Invoke-AdDiscoveryExport {
 [CmdletBinding()]
 param($Environment,$OutputRoot,$CustomerName,$Server,[string[]]$Domain,[switch]$IncludeSecurity)
 Write-Host 'Synthetic credential collector; no AD queries.'
 $inspectionGate=$OutputRoot+'.inspect'
 $gateTimer=[Diagnostics.Stopwatch]::StartNew()
 while((Test-Path -LiteralPath $inspectionGate) -and $gateTimer.Elapsed.TotalSeconds -lt 15){Start-Sleep -Milliseconds 20}
 if($CustomerName -eq 'Fail'){throw 'Synthetic authentication-path collector failure'}
 if($CustomerName -eq 'Wait'){Write-Host 'Waiting for cancellation';Start-Sleep -Seconds 30}
 New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
 $networkUser=Get-Variable adDiscoveryNetworkCredentialUserName -Scope Script -ValueOnly -ErrorAction SilentlyContinue
 [pscustomobject]@{
  Status=if($CustomerName -eq 'Partial'){'Partial'}else{'Complete'};RunRoot=$OutputRoot
  DomainCount=@($Domain).Count;UserCount=1;ComputerCount=2;GroupCount=3;FailedOperations=@();IncompleteOperations=@();LoggingFailed=$false
  LogPath='';ExecutionStatusPath='';LocalIdentity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
  AuthenticationId=[DiscoveryCredentialTests.TokenInspector]::AuthenticationId();NetworkUser=$networkUser
  ReceivedServer=$Server;ReceivedSecurity=[bool]$IncludeSecurity
 }
}
Export-ModuleMember Invoke-AdDiscoveryExport
'@
Set-Content -LiteralPath (Join-Path $root 'Mock.psm1') -Value $fake -Encoding UTF8
$fakeManifest=Join-Path $root 'Mock.psd1'
Set-Content -LiteralPath $fakeManifest -Value "@{RootModule='Mock.psm1';ModuleVersion='1.0';FunctionsToExport=@('Invoke-AdDiscoveryExport')}" -Encoding UTF8

& $module {
    param($Root,$ModuleRoot,$FakeManifest)
    function Assert-Credential { param([bool]$Condition,[string]$Message); if(-not $Condition){throw "Assertion failed: $Message"} }
    $secret='Synthetic-' + [guid]::NewGuid().ToString('N') + '!'
    $user='TEST-NETONLY\reader'
    $credential=New-Object Management.Automation.PSCredential($user,(ConvertTo-SecureString $secret -AsPlainText -Force))
    $parentLogon=[DiscoveryCredentialTests.TokenInspector]::AuthenticationId()
    $parentName=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    try {
        $model=New-AdDiscoveryGuiWindow (Join-Path $ModuleRoot 'Consulting.Toolkit.Discovery.psd1')
        $model.ManifestPath=$FakeManifest
        $model.Controls.OutputInput.Text=Join-Path $Root 'GuiOutput'
        $model.Controls.AlternateCredentialInput.IsChecked=$true
        $model.Controls.CredentialUserInput.Text=$user
        # Synthetic test input only; production reads SecurePassword exclusively.
        $model.Controls.CredentialPasswordInput.Password=$secret
        $saved=Get-AdDiscoveryGuiSettings $model
        $json=$saved | ConvertTo-Json -Depth 8
        Assert-Credential (-not $json.Contains($secret) -and -not $json.Contains($user) -and $saved.UseAlternateCredential) 'Saved settings contain neither username nor password'
        Update-AdDiscoveryGuiPreview $model
        $preview=$model.Controls.CommandPreview.Text
        Assert-Credential ($preview.Contains('-Credential (Get-Credential)') -and -not $preview.Contains($secret) -and -not $preview.Contains($user)) 'Command preview contains a secure prompt, not credential values'
        $run=Start-AdDiscoveryGuiConfiguredRun $model
        try {
            $copy=$model.Controls.CredentialPasswordInput.SecurePassword
            try { Assert-Credential ($copy.Length -eq 0) 'GUI clears its password after launch' } finally { $copy.Dispose() }
            $timer=[Diagnostics.Stopwatch]::StartNew()
            while(-not $run.Process.HasExited -and $timer.Elapsed.TotalSeconds -lt 20){Start-Sleep -Milliseconds 50}
            $envelope=Get-AdDiscoveryProcessEnvelope $run
            Assert-Credential ($envelope.State -eq 'Complete' -and $envelope.Result.AuthenticationId -ne $parentLogon -and $envelope.Result.LocalIdentity -eq $parentName) 'GUI creates a separate network logon while retaining local identity'
        } finally { Close-AdDiscoveryGuiProcess $run }
        $model.Controls.CredentialUserInput.Text='unqualified'
        $model.Controls.CredentialPasswordInput.Password=$secret
        $failed=$false
        try { Start-AdDiscoveryGuiConfiguredRun $model | Out-Null } catch {$failed=$_.Exception.Message -like '*DOMAIN*'}
        $copy=$model.Controls.CredentialPasswordInput.SecurePassword
        try { Assert-Credential ($failed -and $copy.Length -eq 0) 'Rejected credential input clears the GUI password and never starts a worker' } finally {$copy.Dispose()}
        $model.Window.Close()
        Write-Host 'PASS: masked credential model, safe settings/preview, password clearing, and isolated GUI network session'
        $current=New-AdDiscoveryGuiWindow (Join-Path $ModuleRoot 'Consulting.Toolkit.Discovery.psd1')
        $current.ManifestPath=$FakeManifest
        $current.Controls.OutputInput.Text=Join-Path $Root 'CurrentGuiOutput'
        $currentRun=$null
        try {
            $currentRun=Start-AdDiscoveryGuiConfiguredRun $current
            $timer.Restart()
            while(-not $currentRun.Process.HasExited -and $timer.Elapsed.TotalSeconds -lt 20){Start-Sleep -Milliseconds 50}
            $currentResult=Get-AdDiscoveryProcessEnvelope $currentRun
            Assert-Credential ($currentResult.State -eq 'Complete' -and $currentResult.Result.AuthenticationId -eq $parentLogon) 'GUI current-account mode starts without null-credential conversion or an interactive prompt'
        } finally {if($currentRun){Close-AdDiscoveryGuiProcess $currentRun};$current.Window.Close()}

        foreach($engine in @(Get-AdDiscoveryGuiEngines)) {
            foreach($case in @('Complete','Partial','Fail','Wait')) {
                $run=$null;$inspectionGate=$null
                try {
                    $parameters=@{Environment='Source';OutputRoot=(Join-Path $Root ($engine.Id+$case));CustomerName=$case;Server='dc.example.test';Domain=@('example.test');IncludeSecurity=[Management.Automation.SwitchParameter]::new($true)}
                    # Keep the synthetic worker alive until command-line inspection
                    # completes; CIM initialization can outlast a fast collector.
                    $inspectionGate=$parameters.OutputRoot+'.inspect'
                    [IO.File]::WriteAllText($inspectionGate,'inspection')
                    $run=Start-AdDiscoveryGuiProcess $engine $parameters $FakeManifest -Credential $credential
                    $workerInfo=Get-CimInstance Win32_Process -Filter ("ProcessId = " + $run.Process.Id)
                    Assert-Credential ($null -ne $workerInfo) 'Credential worker remains available for command-line inspection'
                    $commandLine=$workerInfo.CommandLine
                    Assert-Credential (-not $commandLine.Contains($secret) -and -not $commandLine.Contains($user)) 'Process command line contains no supplied credential values'
                    Remove-Item -LiteralPath $inspectionGate -Force
                    $timer=[Diagnostics.Stopwatch]::StartNew();$text=''
                    while(-not $run.Process.HasExited -and $timer.Elapsed.TotalSeconds -lt 20) {
                        $text+=@(Read-AdDiscoveryGuiOutput $run) -join ''
                        if($case -eq 'Wait' -and $text.Contains('Waiting for cancellation')){Stop-AdDiscoveryGuiProcess $run}
                        Start-Sleep -Milliseconds 50
                    }
                    Assert-Credential $run.Process.HasExited 'Credential worker completes or stops within the test budget'
                    if($case -eq 'Wait') { Assert-Credential ($run.Stopped -and -not(Test-Path -LiteralPath $run.ResultPath)) 'Stopped credential run cannot produce a successful result' }
                    else {
                        $envelope=Get-AdDiscoveryProcessEnvelope $run
                        $expected=if($case -eq 'Fail'){'Failed'}else{$case}
                        Assert-Credential ($envelope.State -eq $expected) 'Credential runner reports the correct state'
                        if($case -ne 'Fail') {
                            Assert-Credential ($envelope.Result.AuthenticationId -ne $parentLogon -and $envelope.Result.LocalIdentity -eq $parentName -and $envelope.Result.NetworkUser -eq $user) 'Alternate network session is real and records the selected account'
                            Assert-Credential ($envelope.Result.ReceivedServer -eq 'dc.example.test' -and $envelope.Result.ReceivedSecurity) 'Target and switch parameters survive credential launch'
                        }
                    }
                    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secret))
                    foreach($file in @(Get-ChildItem -LiteralPath $run.Folder -File)) {
                        $bytes=[IO.File]::ReadAllBytes($file.FullName)
                        $utf8=[Text.Encoding]::UTF8.GetString($bytes);$utf16=[Text.Encoding]::Unicode.GetString($bytes)
                        Assert-Credential (-not $utf8.Contains($secret) -and -not $utf16.Contains($secret) -and -not $utf8.Contains($encoded)) 'No plaintext or Base64 password appears in requests, output, errors, or results'
                    }
                    Assert-Credential ($credential.Password.Length -gt 0) 'Caller-owned SecureString is not disposed by process launch'
                    Write-Host "PASS: $($engine.Name) alternate credentials $case, network logon identity, parameter transfer, and password non-persistence"
                } finally { if($run){Close-AdDiscoveryGuiProcess $run};if($inspectionGate){Remove-Item -LiteralPath $inspectionGate -Force -ErrorAction SilentlyContinue} }
            }
        }
        $cliParameters=@{Environment='Source';OutputRoot=(Join-Path $Root 'CliOutput');Server='dc.example.test';Domain=@('example.test');IncludeSecurity=$true}
        $cli=Invoke-AdDiscoveryCredentialExport -Parameters $cliParameters -Credential $credential -ManifestPath $FakeManifest
        Assert-Credential ($cli.Status -eq 'Complete' -and $cli.AuthenticationId -ne $parentLogon) 'Command-line helper returns the completed worker result'
        $upn=New-Object Management.Automation.PSCredential('reader@discovery-test.invalid',$credential.Password.Copy())
        $upnRun=$null
        try {
            $upnRun=Start-AdDiscoveryGuiProcess @(Get-AdDiscoveryGuiEngines)[0] $cliParameters $FakeManifest -Credential $upn
            $timer.Restart()
            while(-not $upnRun.Process.HasExited -and $timer.Elapsed.TotalSeconds -lt 20){Start-Sleep -Milliseconds 50}
            $upnResult=Get-AdDiscoveryProcessEnvelope $upnRun
            Assert-Credential ($upnResult.State -eq 'Complete' -and $upnResult.Result.NetworkUser -eq $upn.UserName -and $upnResult.Result.AuthenticationId -ne $parentLogon) 'UPN format starts an isolated network logon without a domain string'
        } finally { if($upnRun){Close-AdDiscoveryGuiProcess $upnRun};$upn.Password.Dispose() }
        function Invoke-AdDiscoveryCredentialExport {
            param($Parameters,$Credential,$ManifestPath)
            Assert-Credential ($Credential -is [Management.Automation.PSCredential] -and -not $Parameters.ContainsKey('Credential') -and $Parameters.IncludeSecurity -eq $true) 'Public wrapper delegates the credential separately from serializable parameters'
            Assert-Credential ($Parameters.OutputRoot -eq 'C:\Discovery' -and $Parameters.Environment -eq 'Source') 'Public credential path preserves defaults'
            [pscustomobject]@{Status='Complete';Delegated=$true}
        }
        $public=Invoke-AdDiscoveryExport -Credential $credential -IncludeSecurity
        Assert-Credential $public.Delegated 'Public Credential option uses the isolated runner'
        function Get-AdAdForest { throw 'Unsafe current-account fallback' }
        $failed=$false
        try { Invoke-AdDiscoveryExport -Credential $null -OutputRoot (Join-Path $Root 'NullCredential') | Out-Null } catch {$failed=$_.Exception.Message -like '*Credential*'}
        Assert-Credential $failed 'An explicitly null credential fails rather than falling back to the current account'
        $failed=$false
        try {Invoke-AdDiscoveryExport -Credential 'TEST-NETONLY\reader' -OutputRoot (Join-Path $Root 'StringCredential') | Out-Null}catch{$failed=$_.Exception.Message -like '*PSCredential*'}
        Assert-Credential $failed 'A string credential is rejected without an implicit password prompt'
        $failed=$false
        try { Start-AdDiscoveryGuiProcess @(Get-AdDiscoveryGuiEngines)[0] @{Credential=$credential} $FakeManifest | Out-Null } catch {$failed=$true}
        Assert-Credential $failed 'Accidental credential serialization is rejected'
        Write-Host "PASS: command-line Credential delegation, defaults, result handling, and serialization guard; outputs: $Root"
    } finally { $credential.Password.Dispose() }
} $root $moduleRoot $fakeManifest
