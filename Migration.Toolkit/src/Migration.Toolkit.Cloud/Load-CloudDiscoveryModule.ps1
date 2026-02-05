<#
.SYNOPSIS
Resolves Microsoft Graph SDK module conflicts and loads Migration.Toolkit.Cloud.

.DESCRIPTION
Cleans assembly conflicts from previous Graph SDK versions in the current session
and properly initializes the Migration.Toolkit.Cloud module.

This script handles the common "Assembly already loaded" error that occurs when
different versions of Microsoft.Graph modules are loaded in the same PowerShell session.

.EXAMPLE
.\Load-CloudDiscoveryModule.ps1

.NOTES
If this doesn't work, you may need to start a completely fresh PowerShell session.
#>

[CmdletBinding()]
param()

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Loading Migration.Toolkit.Cloud Module" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Step 1: Unload all Microsoft Graph modules
Write-Host "Cleaning up Microsoft Graph modules from current session..." -ForegroundColor Yellow
$modules = Get-Module Microsoft.Graph.* -ErrorAction SilentlyContinue
if ($modules) {
    Write-Host "  Unloading $($modules.Count) Microsoft Graph module(s)..."
    $modules | Remove-Module -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ Microsoft Graph modules unloaded" -ForegroundColor Green
}
else {
    Write-Host "  (No Microsoft Graph modules currently loaded)" -ForegroundColor Gray
}

# Step 2: Unload Exchange Online module
Write-Host "Cleaning up Exchange Online module..." -ForegroundColor Yellow
$exModule = Get-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue
if ($exModule) {
    Write-Host "  Unloading ExchangeOnlineManagement..."
    $exModule | Remove-Module -Force -ErrorAction SilentlyContinue
    Write-Host "  ✓ ExchangeOnlineManagement unloaded" -ForegroundColor Green
}
else {
    Write-Host "  (No ExchangeOnlineManagement module currently loaded)" -ForegroundColor Gray
}

# Step 3: Import Migration.Toolkit.Cloud
Write-Host "`nImporting Migration.Toolkit.Cloud module..." -ForegroundColor Cyan
try {
    $modulePath = "C:\Users\PLagana\OneDrive - Quest\Documents\GitHub\Migration.Toolkit\src\Migration.Toolkit.Cloud\Migration.Toolkit.Cloud.psd1"

    if (-not (Test-Path $modulePath)) {
        throw "Module manifest not found: $modulePath"
    }

    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "✓ Migration.Toolkit.Cloud module loaded successfully`n" -ForegroundColor Green

    # Step 4: Verify functions are available
    Write-Host "Verifying functions..." -ForegroundColor Cyan
    $functions = Get-Command -Module Migration.Toolkit.Cloud | Select-Object -ExpandProperty Name
    Write-Host "✓ $($functions.Count) functions available:`n" -ForegroundColor Green

    $functions | Sort-Object | ForEach-Object { Write-Host "    • $_" -ForegroundColor Gray }

    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Ready to Connect" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

    Write-Host "Next step - Connect to your tenant:" -ForegroundColor White
    Write-Host "  Connect-AzCloudTenant -TenantId `"your-tenant.onmicrosoft.com`" -AuthType Interactive" -ForegroundColor Cyan
    Write-Host ""

}
catch {
    Write-Host "✗ Failed to load module: $($_.Exception.Message)`n" -ForegroundColor Red
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "  1. Close ALL PowerShell windows" -ForegroundColor White
    Write-Host "  2. Open a brand new PowerShell window" -ForegroundColor White
    Write-Host "  3. Run this script again" -ForegroundColor White
    Write-Host ""
    Write-Host "If the issue persists, check:" -ForegroundColor Yellow
    Write-Host "  • Your Microsoft.Graph modules are up to date" -ForegroundColor White
    Write-Host "  • Run: .\Install-CloudDiscoveryPrerequisites.ps1 -Force" -ForegroundColor White
    Write-Host ""
    exit 1
}
