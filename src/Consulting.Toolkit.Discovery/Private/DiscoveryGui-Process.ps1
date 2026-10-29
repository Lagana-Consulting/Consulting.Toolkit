function Start-AdDiscoveryGuiProcess {
    param([Parameter(Mandatory)]$Engine, [Parameter(Mandatory)][hashtable]$Parameters,
        [Parameter(Mandatory)][string]$ManifestPath,
        [object]$Credential)
    $root = Split-Path -Parent $ManifestPath
    if ($null -ne $Credential) {
        if ($Credential -isnot [System.Management.Automation.PSCredential]) { throw 'Credential must be a PSCredential obtained with Get-Credential.' }
        Assert-AdDiscoveryCredential $Credential
    }
    if (-not ('Consulting.Toolkit.Discovery.CredentialProcess' -as [type])) {
        Add-Type -Path (Join-Path $root 'Gui\DiscoveryGuiJob.cs') -ErrorAction Stop
    }
    foreach ($value in $Parameters.Values) {
        if ($value -is [System.Management.Automation.PSCredential] -or $value -is [System.Security.SecureString]) {
            throw 'Credentials must be passed through the secure Credential argument, never through serialized parameters.'
        }
    }
    if ($Parameters.ContainsKey('Credential')) { throw 'Credential cannot be serialized into a runner request.' }
    $safeParameters=@{}
    foreach ($name in $Parameters.Keys) {
        $value=$Parameters[$name]
        $safeParameters[$name]=if ($value -is [System.Management.Automation.SwitchParameter]) { [bool]$value } else { $value }
    }
    $launchId=[guid]::NewGuid().ToString('N')
    $folder=Join-Path ([IO.Path]::GetTempPath()) ('ConsultingDiscoveryGui\' + $launchId)
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null
    $requestPath=Join-Path $folder 'request.json'
    $resultPath=Join-Path $folder 'result.clixml'
    $stdout=Join-Path $folder 'console.log'
    $stderr=Join-Path $folder 'errors.log'
    [pscustomobject]@{LaunchId=$launchId;ManifestPath=$ManifestPath;Parameters=$safeParameters;ResultPath=$resultPath;
        ConsolePath=$stdout;ErrorPath=$stderr;
        AuthenticationMode=if($Credential){'AlternateNetwork'}else{'CurrentWindows'};
        NetworkUserName=if($Credential){$Credential.UserName}else{''}} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $requestPath -Encoding UTF8 -ErrorAction Stop
    $worker=Join-Path $root 'Gui\Invoke-DiscoveryGuiWorker.ps1'
    $job=New-Object Consulting.Toolkit.Discovery.DiscoveryProcessJob
    $process=$null
    try {
        # User values travel in JSON, never through executable command text.
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $worker + '" -RequestPath "' + $requestPath + '"'
        if ($Credential) {
            $process=[Consulting.Toolkit.Discovery.CredentialProcess]::Start($Credential.UserName,$Credential.Password,$Engine.Path,$arguments,$root,$job)
        } else {
            $process=Start-Process -FilePath $Engine.Path -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -ErrorAction Stop
            $job.Assign($process)
        }
        return [pscustomobject]@{LaunchId=$launchId;Process=$process;Job=$job;Folder=$folder;ResultPath=$resultPath;Stdout=$stdout;Stderr=$stderr;Readers=@{};StartedUtc=[datetime]::UtcNow;Stopped=$false;OutputRoot=[string]$Parameters.OutputRoot}
    } catch {
        $job.Dispose()
        if ($process -and -not $process.HasExited) { $process.Kill() }
        $_.Exception.Data['LaunchFolder']=$folder
        throw
    }
}

function Read-AdDiscoveryGuiOutput {
    param([Parameter(Mandatory)]$Run)
    foreach ($path in @($Run.Stdout,$Run.Stderr)) {
        if (-not $Run.Readers.ContainsKey($path) -and (Test-Path -LiteralPath $path)) {
            $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $Run.Readers[$path]=New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
        }
        if ($Run.Readers.ContainsKey($path)) {
            $buffer=New-Object char[] 32768
            # A bounded read keeps one busy worker from monopolizing the UI thread.
            $count=$Run.Readers[$path].Read($buffer,0,$buffer.Length)
            if ($count) { -join $buffer[0..($count-1)] }
        }
    }
}

function Stop-AdDiscoveryGuiProcess {
    param([Parameter(Mandatory)]$Run)
    $Run.Stopped=$true
    $Run.Job.Dispose()
}

function Close-AdDiscoveryGuiProcess {
    param([Parameter(Mandatory)]$Run)
    foreach ($reader in $Run.Readers.Values) { $reader.Dispose() }
    $Run.Readers.Clear()
    $Run.Job.Dispose()
    $Run.Process.Dispose()
}
