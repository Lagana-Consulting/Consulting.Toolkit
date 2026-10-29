[CmdletBinding()]
param([Parameter(Mandatory)][string]$RequestPath)
. ([IO.Path]::Combine($PSScriptRoot,'Initialize-DiscoveryGuiEnvironment.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$InformationPreference='Continue'
$VerbosePreference='SilentlyContinue'
$DebugPreference='SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$request=$null
$consoleWriter=$null; $errorWriter=$null
try {
    $request = Get-Content -LiteralPath $RequestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    # The worker owns its log handles, including when Windows creates it under
    # alternate network credentials without inherited standard handles.
    $consoleWriter=New-Object IO.StreamWriter($request.ConsolePath,$false,(New-Object Text.UTF8Encoding($false)))
    $errorWriter=New-Object IO.StreamWriter($request.ErrorPath,$false,(New-Object Text.UTF8Encoding($false)))
    $consoleWriter.AutoFlush=$true; $errorWriter.AutoFlush=$true
    [Console]::SetOut($consoleWriter); [Console]::SetError($errorWriter)
    Import-Module -Name $request.ManifestPath -Force -WarningAction SilentlyContinue -ErrorAction Stop
    $command = Get-Command Invoke-AdDiscoveryExport -CommandType Function -ErrorAction Stop
    if ($request.AuthenticationMode -eq 'AlternateNetwork') {
        & $command.Module { param($userName) $script:adDiscoveryNetworkCredentialUserName=$userName } $request.NetworkUserName
    }
    $parameters=@{}
    foreach ($property in $request.Parameters.PSObject.Properties) {
        if (-not $command.Parameters.ContainsKey($property.Name)) { throw "Unsupported discovery parameter '$($property.Name)' for this PowerShell engine." }
        $parameters[$property.Name]=$property.Value
    }
    $result=$null
    # Keep the result object separate from human-readable host/error streams.
    & $command @parameters *>&1 | ForEach-Object {
        if ($_ -and $_.PSObject.Properties['RunRoot'] -and $_.PSObject.Properties['Status']) { $result=$_ }
        else { [Console]::WriteLine([string]$_) }
    }
    if (-not $result) { throw 'Discovery returned no run result. Review the launcher output and discovery logs.' }
    $envelope = [pscustomobject]@{LaunchId=$request.LaunchId;State=[string]$result.Status;Result=$result;ErrorMessage='';ErrorDetails=''}
    $envelope | Export-Clixml -LiteralPath $request.ResultPath -Depth 12 -Force -ErrorAction Stop
    if ($result.Status -eq 'Complete') { exit 0 }
    exit 2
} catch {
    $failure=$_
    [Console]::Error.WriteLine($failure.ToString())
    [Console]::Error.WriteLine($failure.ScriptStackTrace)
    if ($request -and $request.PSObject.Properties['ResultPath']) {
        [pscustomobject]@{LaunchId=$request.LaunchId;State='Failed';Result=$null;ErrorMessage=$failure.Exception.Message;ErrorDetails=$failure.ToString() + [Environment]::NewLine + $failure.ScriptStackTrace} |
            Export-Clixml -LiteralPath $request.ResultPath -Depth 12 -Force -ErrorAction Stop
    }
    exit 1
} finally {
    if ($consoleWriter) { $consoleWriter.Dispose() }
    if ($errorWriter) { $errorWriter.Dispose() }
}
