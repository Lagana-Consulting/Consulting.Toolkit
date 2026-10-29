# Start-Process inherits PSModulePath unchanged. Put the selected engine's
# built-in modules first so a PowerShell 7 parent can launch Windows PowerShell
# (and vice versa) without loading the other engine's utility modules.
$engineModulePaths=@([IO.Path]::Combine($PSHOME,'Modules'))
$documents=[Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$programFiles=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$moduleDirectory=if ($PSVersionTable.PSEdition -eq 'Desktop') { 'WindowsPowerShell' } else { 'PowerShell' }
$engineModulePaths+=[IO.Path]::Combine($documents,$moduleDirectory,'Modules')
$engineModulePaths+=[IO.Path]::Combine($programFiles,$moduleDirectory,'Modules')
foreach ($candidatePath in ([Environment]::GetEnvironmentVariable('PSModulePath') -split ';')) {
    if (-not $candidatePath) { continue }
    if ($PSVersionTable.PSEdition -eq 'Desktop' -and $candidatePath -match '[\\/]PowerShell[\\/]\d+(\.\d+)*[\\/]Modules[\\/]?$') { continue }
    if ($candidatePath -notin $engineModulePaths) { $engineModulePaths+=$candidatePath }
}
[Environment]::SetEnvironmentVariable('PSModulePath',($engineModulePaths -join ';'),'Process')
