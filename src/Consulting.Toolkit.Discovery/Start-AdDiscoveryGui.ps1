[CmdletBinding()]
param([string]$SettingsPath)
$ErrorActionPreference='Stop'
try {
    . ([IO.Path]::Combine($PSScriptRoot,'Gui','Initialize-DiscoveryGuiEnvironment.ps1'))
    Import-Module (Join-Path $PSScriptRoot 'Consulting.Toolkit.Discovery.psd1') -Force -ErrorAction Stop
    Show-AdDiscoveryGui @PSBoundParameters
} catch {
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show($_.Exception.Message,'Discovery launcher could not start',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Error) | Out-Null
    throw
}
