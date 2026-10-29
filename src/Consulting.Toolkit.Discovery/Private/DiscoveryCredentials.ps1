function Assert-AdDiscoveryCredential {
    param([Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential)
    if ($Credential.UserName -notmatch '^(?:[^\\\s]+\\[^\\]+|[^@\s]+@[^@\s]+)$') {
        throw 'Enter the alternate account as DOMAIN\user or user@domain.'
    }
    if (-not $Credential.Password -or $Credential.Password.Length -eq 0) { throw 'Enter a password for the alternate account.' }
}

function Get-AdDiscoveryGuiCredential {
    param([Parameter(Mandatory)]$Model)
    if (-not $Model.Controls.AlternateCredentialInput.IsChecked) { return $null }
    $userName=$Model.Controls.CredentialUserInput.Text.Trim()
    $secret=$Model.Controls.CredentialPasswordInput.SecurePassword
    try {
        $credential=New-Object System.Management.Automation.PSCredential($userName,$secret)
        Assert-AdDiscoveryCredential $credential
        return $credential
    } catch { $secret.Dispose(); throw }
}

function Start-AdDiscoveryGuiConfiguredRun {
    param([Parameter(Mandatory)]$Model)
    $credential=$null
    try {
        $parameters=ConvertTo-AdDiscoveryGuiParameters (Get-AdDiscoveryGuiSettings $Model) -SupportsProgressAction $Model.Controls.EngineInput.SelectedItem.SupportsProgressAction
        $credential=Get-AdDiscoveryGuiCredential $Model
        return Start-AdDiscoveryGuiProcess $Model.Controls.EngineInput.SelectedItem $parameters $Model.ManifestPath -Credential $credential
    } finally {
        $Model.Controls.CredentialPasswordInput.Clear()
        if ($credential) { $credential.Password.Dispose() }
    }
}

function Get-AdDiscoveryProcessEnvelope {
    param([Parameter(Mandatory)]$Run)
    if (-not $Run.Process.HasExited) { throw 'The discovery runner is still active.' }
    if (-not (Test-Path -LiteralPath $Run.ResultPath)) { throw "The runner exited without a result. Review launcher logs in '$($Run.Folder)'." }
    $envelope=Import-Clixml -LiteralPath $Run.ResultPath -ErrorAction Stop
    if ($envelope.LaunchId -ne $Run.LaunchId) { throw 'The runner result does not belong to this launch.' }
    if ($envelope.State -notin @('Complete','Partial','Failed')) { throw "Unexpected runner result '$($envelope.State)'." }
    $expectedExit=switch ($envelope.State) { Complete {0} Partial {2} Failed {1} }
    if ($Run.Process.ExitCode -ne $expectedExit) { throw "The runner exit code does not match its '$($envelope.State)' result." }
    return $envelope
}

function Invoke-AdDiscoveryCredentialExport {
    param([Parameter(Mandatory)][hashtable]$Parameters,
        [Parameter(Mandatory)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory)][string]$ManifestPath)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Alternate discovery credentials require Windows.' }
    Assert-AdDiscoveryCredential $Credential
    $engineId=if ($PSVersionTable.PSEdition -eq 'Desktop') { 'WindowsPowerShell' } else { 'PowerShell7' }
    $engine=Get-AdDiscoveryGuiEngines | Where-Object Id -eq $engineId | Select-Object -First 1
    if (-not $engine) { throw 'The current PowerShell engine could not be located for the alternate-credential runner.' }
    $run=$null
    try {
        $run=Start-AdDiscoveryGuiProcess -Engine $engine -Parameters $Parameters -ManifestPath $ManifestPath -Credential $Credential
        Write-Host 'Discovery is using alternate network credentials. Local file permissions remain those of the signed-in Windows account.'
        do {
            foreach ($text in @(Read-AdDiscoveryGuiOutput $run)) { Write-Host -NoNewline $text }
            if (-not $run.Process.HasExited) { Start-Sleep -Milliseconds 100 }
        } while (-not $run.Process.HasExited)
        do {
            $remaining=@(Read-AdDiscoveryGuiOutput $run)
            foreach ($text in $remaining) { Write-Host -NoNewline $text }
        } while ($remaining.Count -gt 0)
        $envelope=Get-AdDiscoveryProcessEnvelope $run
        if ($envelope.State -eq 'Failed') { throw "Alternate-credential discovery failed: $($envelope.ErrorMessage) Launcher logs: $($run.Folder)" }
        return $envelope.Result
    } finally { if ($run) { Close-AdDiscoveryGuiProcess $run } }
}
