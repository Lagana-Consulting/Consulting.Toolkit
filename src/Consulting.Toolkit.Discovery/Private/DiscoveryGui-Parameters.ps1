function Get-AdDiscoveryGuiEngines {
    $windowsRoot = [Environment]::GetEnvironmentVariable('WINDIR')
    $windowsPs = Join-Path $windowsRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $windowsPs = Join-Path $windowsRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    }
    if (Test-Path -LiteralPath $windowsPs) {
        [pscustomobject]@{Id='WindowsPowerShell';Name='Windows PowerShell 5.1 (recommended)';Path=$windowsPs;SupportsProgressAction=$false}
    }
    $core = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($core) {
        $version = (Get-Item -LiteralPath $core.Source).VersionInfo.FileVersion
        $supportsProgress = $version -match '^(\d+)\.(\d+)' -and ([int]$Matches[1] -gt 7 -or ([int]$Matches[1] -eq 7 -and [int]$Matches[2] -ge 4))
        [pscustomobject]@{Id='PowerShell7';Name='PowerShell 7';Path=$core.Source;SupportsProgressAction=[bool]$supportsProgress}
    }
}

function Get-AdDiscoveryGuiCommonOptions {
    param([bool]$SupportsProgressAction)
    @(
        [pscustomobject]@{Name='Verbose';Kind='Switch';Hint='Include verbose messages'}
        [pscustomobject]@{Name='Debug';Kind='Switch';Hint='Include debug messages; the runner is noninteractive'}
        [pscustomobject]@{Name='ErrorAction';Kind='Action';Hint='PowerShell error handling'}
        [pscustomobject]@{Name='WarningAction';Kind='Action';Hint='PowerShell warning handling'}
        [pscustomobject]@{Name='InformationAction';Kind='Action';Hint='PowerShell information stream handling'}
        if ($SupportsProgressAction) { [pscustomobject]@{Name='ProgressAction';Kind='Action';Hint='PowerShell progress handling (7.4+)'} }
        [pscustomobject]@{Name='ErrorVariable';Kind='Text';Hint='Capture errors in a variable within the runner'}
        [pscustomobject]@{Name='WarningVariable';Kind='Text';Hint='Capture warnings in a variable within the runner'}
        [pscustomobject]@{Name='InformationVariable';Kind='Text';Hint='Capture information in a variable within the runner'}
        [pscustomobject]@{Name='OutVariable';Kind='Text';Hint='Capture output in a variable within the runner'}
        [pscustomobject]@{Name='OutBuffer';Kind='Integer';Hint='PowerShell output buffer size (zero or greater)'}
        [pscustomobject]@{Name='PipelineVariable';Kind='Text';Hint='Pipeline variable within the runner'}
    )
}

function ConvertTo-AdDiscoveryGuiParameters {
    param([Parameter(Mandatory)][hashtable]$Settings, [bool]$SupportsProgressAction)
    $environment = ([string]$Settings.Environment).Trim()
    if (-not $environment) { throw 'Enter an environment label.' }
    if ($environment.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $environment -in @('.','..')) {
        throw 'The environment label cannot contain filename separators or reserved characters.'
    }
    $outputRoot = [Environment]::ExpandEnvironmentVariables(([string]$Settings.OutputRoot).Trim())
    if (-not $outputRoot -or -not [IO.Path]::IsPathRooted($outputRoot) -or
        [IO.Path]::GetPathRoot($outputRoot) -in @('\','/')) {
        throw 'Choose an absolute output folder, such as C:\Discovery or \\server\share\Discovery.'
    }
    $parameters = @{Environment=$environment;OutputRoot=$outputRoot}
    foreach ($name in @('CustomerName','Server')) {
        $value = ([string]$Settings[$name]).Trim()
        if ($value) { $parameters[$name] = $value }
    }
    $domains = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($value in @($Settings.Domain)) {
        foreach ($domain in ([string]$value -split '[,;\s]+')) {
            if ($domain -and -not $seen.ContainsKey($domain)) { $seen[$domain]=$true; $domains.Add($domain) }
        }
    }
    if ($domains.Count) { $parameters.Domain=$domains.ToArray() }
    if ((ConvertTo-AdAssessmentBoolean $Settings.IncludeSecurity -Field 'IncludeSecurity') -eq $true) { $parameters.IncludeSecurity=$true }
    $common = if ($Settings.ContainsKey('CommonParameters') -and $Settings.CommonParameters) { $Settings.CommonParameters } else { @{} }
    $definitions = @(Get-AdDiscoveryGuiCommonOptions -SupportsProgressAction $SupportsProgressAction)
    foreach ($name in $common.Keys) {
        $definition = $definitions | Where-Object Name -eq $name | Select-Object -First 1
        if (-not $definition) { throw "PowerShell option '$name' is unavailable in the selected engine." }
        $value = $common[$name]
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value) -or [string]$value -eq '(default)') { continue }
        switch ($definition.Kind) {
            Switch { if ((ConvertTo-AdAssessmentBoolean $value -Field $name) -eq $true) { $parameters[$name]=$true } }
            Integer {
                $number = ConvertTo-AdAssessmentInteger $value -Field $name
                if ($number -lt 0) { throw "$name must be zero or greater." }
                $parameters[$name]=$number
            }
            Action {
                if ([string]$value -notin @('Continue','SilentlyContinue','Stop','Ignore','Inquire','Break','Suspend')) { throw "Invalid $name value '$value'." }
                $parameters[$name]=[string]$value
            }
            default { $parameters[$name]=([string]$value).Trim() }
        }
    }
    return $parameters
}

function Format-AdDiscoveryGuiCommand {
    param([Parameter(Mandatory)][hashtable]$Parameters, [string]$ManifestPath, [switch]$UseAlternateCredential)
    function Quote-AdGuiLiteral([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
    $parts = New-Object System.Collections.Generic.List[string]
    if ($Parameters.ContainsKey('Credential')) { throw 'Format credential prompts separately; never format a credential value.' }
    foreach ($name in @('Environment','OutputRoot','CustomerName','Server','Domain','IncludeSecurity') + @($Parameters.Keys | Where-Object { $_ -notin @('Environment','OutputRoot','CustomerName','Server','Domain','IncludeSecurity') } | Sort-Object)) {
        if (-not $Parameters.ContainsKey($name)) { continue }
        $value=$Parameters[$name]
        if ($value -is [bool]) { if ($value) { $parts.Add('-' + $name) } }
        elseif ($name -eq 'Domain') { $parts.Add('-Domain @(' + ((@($value) | ForEach-Object { Quote-AdGuiLiteral $_ }) -join ', ') + ')') }
        elseif ($value -is [int]) { $parts.Add('-' + $name + ' ' + $value) }
        else { $parts.Add('-' + $name + ' ' + (Quote-AdGuiLiteral ([string]$value))) }
    }
    if ($UseAlternateCredential) { $parts.Add('-Credential (Get-Credential)') }
    $command = 'Invoke-AdDiscoveryExport'
    if ($parts.Count) { $command += ' ' + [char]96 + [Environment]::NewLine + '  ' + ($parts -join (' ' + [char]96 + [Environment]::NewLine + '  ')) }
    if ($ManifestPath) { $command = 'Import-Module ' + (Quote-AdGuiLiteral $ManifestPath) + ' -Force' + [Environment]::NewLine + [Environment]::NewLine + $command }
    return $command
}

function Import-AdDiscoveryGuiSettings {
    param([Parameter(Mandatory)][string]$Path)
    $document = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (-not $document.PSObject.Properties['SchemaVersion'] -or $document.SchemaVersion -ne 1) { throw 'This is not a supported discovery settings file.' }
    $settings = @{Environment='Source';OutputRoot='C:\Discovery';CustomerName='';Server='';Domain=@();IncludeSecurity=$false;EngineId='WindowsPowerShell';CommonParameters=@{};UseAlternateCredential=$false}
    foreach ($property in $document.PSObject.Properties) {
        if ($property.Name -eq 'SchemaVersion') { continue }
        if (-not $settings.ContainsKey($property.Name)) { throw "Unknown discovery setting '$($property.Name)'." }
        if ($property.Name -eq 'CommonParameters') {
            foreach ($option in $property.Value.PSObject.Properties) { $settings.CommonParameters[$option.Name]=$option.Value }
        } else { $settings[$property.Name]=$property.Value }
    }
    return $settings
}
