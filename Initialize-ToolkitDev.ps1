$src = (Resolve-Path "$PSScriptRoot\..\src").Path
if ($env:PSModulePath -notlike "*$src*") {
    $env:PSModulePath = "$src;$env:PSModulePath"
}

Import-Module Consulting.Toolkit.Discovery -Force
Import-Module Migration.Toolkit.Analysis -Force
Import-Module Migration.Toolkit.Assessment -Force
#Import-Module Identity.Security.Assessment.Toolkit -Force
Import-Module Cloud.Toolkit.Discovery -Force

Write-Host "Toolkit modules loaded."
