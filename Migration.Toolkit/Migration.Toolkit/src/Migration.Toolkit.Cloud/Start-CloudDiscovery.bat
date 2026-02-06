@echo off
REM Start fresh PowerShell window with Migration.Toolkit.Cloud module loaded
REM This avoids assembly conflicts from previous module versions

cd /d "C:\Users\PLagana\OneDrive - Quest\Documents\GitHub\Migration.Toolkit\src\Migration.Toolkit.Cloud"

powershell.exe -NoExit -Command "Import-Module '.\Migration.Toolkit.Cloud.psd1' -Force; Write-Host '`n✓ Migration.Toolkit.Cloud module loaded successfully`n' -ForegroundColor Green; Get-Command -Module Migration.Toolkit.Cloud | Select-Object -ExpandProperty Name | Sort-Object | ForEach-Object { Write-Host ('  • ' + $_) -ForegroundColor Gray }; Write-Host '`nReady to connect. Example:' -ForegroundColor Cyan; Write-Host '  Connect-AzCloudTenant -TenantId `"tenant.onmicrosoft.com`" -AuthType Interactive`n' -ForegroundColor Gray"
