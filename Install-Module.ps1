# Server Installation Script for Migration.Toolkit PowerShell Module
$zip = "C:\Temp\Migration.Toolkit.1.0.0.zip"
$dest = Join-Path ($env:USERPROFILE + "\Documents\WindowsPowerShell\Modules") "Migration.Toolkit"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Expand-Archive -Path $zip -DestinationPath $dest -Force
Import-Module Migration.Toolkit -Force

# Local Installation Script for Migration.Toolkit.Analysis PowerShell Module
$zip = "C:\Temp\Migration.Toolkit.Analysis.1.0.0.zip"
$dest = Join-Path ($env:USERPROFILE + "\Documents\PowerShell\Modules") "Migration.Toolkit.Analysis"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Expand-Archive -Path $zip -DestinationPath $dest -Force
Import-Module Migration.Toolkit.Analysis -Force

