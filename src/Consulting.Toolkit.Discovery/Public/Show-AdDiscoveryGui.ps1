function Show-AdDiscoveryGui {
    <#
    .SYNOPSIS
    Opens the Windows desktop launcher for Invoke-AdDiscoveryExport.
    .DESCRIPTION
    Exposes all discovery parameters and common PowerShell options, a command
    preview, saved JSON settings, live output, cancellation, and run results.
    Collection starts only when the operator selects Start discovery. The worker
    runs in a separate process under the current Windows account.
    .PARAMETER SettingsPath
    Optional JSON settings file previously saved by the launcher.
    .EXAMPLE
    Show-AdDiscoveryGui
    #>
    [CmdletBinding()]
    param([string]$SettingsPath)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'The discovery GUI requires Windows.' }
    $manifestPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'Consulting.Toolkit.Discovery.psd1'
    Write-Verbose ('GUI host: PowerShell {0}, apartment {1}' -f $PSVersionTable.PSVersion,[Threading.Thread]::CurrentThread.ApartmentState)
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        $engine=Get-AdDiscoveryGuiEngines | Select-Object -First 1
        $launcher=Join-Path (Split-Path -Parent $PSScriptRoot) 'Start-AdDiscoveryGui.ps1'
        $arguments='-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '"'
        if ($SettingsPath) { $arguments+=' -SettingsPath "' + (Resolve-Path -LiteralPath $SettingsPath -ErrorAction Stop).ProviderPath + '"' }
        # Let the interactive WPF window show normally; the engine switch hides
        # its console without applying a hidden startup state to the GUI itself.
        Start-Process -FilePath $engine.Path -ArgumentList $arguments -WindowStyle Normal -ErrorAction Stop | Out-Null
        return
    }
    $model=New-AdDiscoveryGuiWindow -ManifestPath $manifestPath -SettingsPath $SettingsPath
    Write-Verbose 'Discovery window constructed; opening the window.'
    try { $model.Window.ShowDialog() | Out-Null } finally {
        $model.Timer.Stop()
        if ($model.Run) { Close-AdDiscoveryGuiProcess $model.Run; $model.Run=$null }
    }
}
