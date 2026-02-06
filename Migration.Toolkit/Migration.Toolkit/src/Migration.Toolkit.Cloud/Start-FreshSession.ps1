<#
.SYNOPSIS
Fresh-start helper script for Migration.Toolkit.Cloud

.DESCRIPTION
Opens a new PowerShell process with a clean environment and loads Migration.Toolkit.Cloud.
Avoids assembly conflicts from previous module loads in the current session.

.NOTES
Use this if you're getting "Assembly already loaded" errors.
#>

$cloudModulePath = "C:\Users\PLagana\OneDrive - Quest\Documents\GitHub\Migration.Toolkit\src\Migration.Toolkit.Cloud"

$command = @"
Import-Module '$cloudModulePath\Migration.Toolkit.Cloud.psd1' -Force
`$funcs = Get-Command -Module Migration.Toolkit.Cloud | Select-Object -ExpandProperty Name | Sort-Object
Write-Host "`n✓ Migration.Toolkit.Cloud module loaded`n" -ForegroundColor Green
Write-Host "Available functions:" -ForegroundColor Cyan
`$funcs | ForEach-Object { Write-Host "  • `$_" -ForegroundColor Gray }
Write-Host "`nReady to connect. Example:" -ForegroundColor Cyan
Write-Host "  Connect-AzCloudTenant -TenantId `"tenant.onmicrosoft.com`" -AuthType Interactive`n" -ForegroundColor Gray
cd '$cloudModulePath'
"@

Start-Process powershell.exe -ArgumentList "-NoExit", "-Command `"$command`""
