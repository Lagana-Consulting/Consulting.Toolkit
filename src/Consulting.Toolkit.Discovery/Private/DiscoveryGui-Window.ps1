function New-AdDiscoveryGuiWindow {
    param([Parameter(Mandatory)][string]$ManifestPath, [string]$SettingsPath)
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms -ErrorAction Stop
    $xamlPath=Join-Path (Split-Path -Parent $ManifestPath) 'Gui\Discovery.xaml'
    $reader=New-Object System.Xml.XmlNodeReader ([xml][IO.File]::ReadAllText($xamlPath))
    try { $window=[Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
    $controls=@{}
    foreach ($match in [regex]::Matches([IO.File]::ReadAllText($xamlPath),'(?<!:)Name="([A-Za-z]+)"')) {
        $controls[$match.Groups[1].Value]=$window.FindName($match.Groups[1].Value)
    }
    $model=[pscustomobject]@{Window=$window;Controls=$controls;ManifestPath=$ManifestPath;Module=$ExecutionContext.SessionState.Module;
        CommonControls=@{};Run=$null;LastResult=$null;LaunchLogFolder='';OpenRunPath='';Timer=$null;Initializing=$true}
    $engines=@(Get-AdDiscoveryGuiEngines)
    if (-not $engines.Count) { throw 'No supported PowerShell executable was found.' }
    $controls.EngineInput.ItemsSource=$engines
    $controls.EngineInput.SelectedIndex=0
    $controls.AccountText.Text='Running as ' + [Environment]::UserDomainName + '\' + [Environment]::UserName
    Set-AdDiscoveryGuiCommonControls $model @{}
    if ($SettingsPath) { Set-AdDiscoveryGuiSettings $model (Import-AdDiscoveryGuiSettings $SettingsPath) }

    foreach ($pair in @(
        @('BrowseOutputButton','Browse'),@('CopyCommandButton','Copy'),@('SaveSettingsButton','Save'),@('LoadSettingsButton','Load'),
        @('StartButton','Start'),@('StopButton','Stop'),@('LauncherLogsButton','LauncherLogs'),@('OpenRunButton','OpenRun'),
        @('OpenLogButton','OpenLog'),@('OpenStatusButton','OpenStatus'),@('OpenIndexButton','OpenIndex')
    )) {
        $action=$pair[1]
        $handler={ & $model.Module { param($m,$a) Invoke-AdDiscoveryGuiAction $m $a } $model $action }.GetNewClosure()
        $controls[$pair[0]].Add_Click($handler)
    }
    $refresh={ & $model.Module { param($m) Update-AdDiscoveryGuiPreview $m } $model }.GetNewClosure()
    foreach ($name in @('OutputInput','CustomerInput','ServerInput','DomainsInput')) { $controls[$name].Add_TextChanged($refresh) }
    $controls.EnvironmentInput.Add_SelectionChanged($refresh)
    $controls.EnvironmentInput.AddHandler([Windows.Controls.Primitives.TextBoxBase]::TextChangedEvent,[Windows.RoutedEventHandler]$refresh)
    $controls.SecurityInput.Add_Checked($refresh); $controls.SecurityInput.Add_Unchecked($refresh)
    $authenticationChanged={
        & $model.Module {
            param($m)
            Set-AdDiscoveryGuiAuthenticationControls $m
            Update-AdDiscoveryGuiPreview $m
        } $model
    }.GetNewClosure()
    $controls.AlternateCredentialInput.Add_Checked($authenticationChanged)
    $controls.AlternateCredentialInput.Add_Unchecked($authenticationChanged)
    Set-AdDiscoveryGuiAuthenticationControls $model
    $controls.EngineInput.Add_SelectionChanged({
        & $model.Module {
            param($m)
            if ($m.Initializing) { return }
            $old=(Get-AdDiscoveryGuiSettings $m).CommonParameters
            Set-AdDiscoveryGuiCommonControls $m $old
            Update-AdDiscoveryGuiPreview $m
        } $model
    }.GetNewClosure())
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[timespan]::FromMilliseconds(300)
    $timer.Add_Tick({ & $model.Module { param($m) Update-AdDiscoveryGuiRun $m } $model }.GetNewClosure())
    $model.Timer=$timer
    $window.Add_Closing({
        param($sender,$eventArgs)
        if ($model.Run -and -not $model.Run.Process.HasExited) {
            $choice=[Windows.MessageBox]::Show($model.Window,'Discovery is still running. Stop the run and close this window? Completed files will remain.','Stop discovery?',[Windows.MessageBoxButton]::YesNo,[Windows.MessageBoxImage]::Question)
            if ($choice -ne [Windows.MessageBoxResult]::Yes) { $eventArgs.Cancel=$true; return }
        }
        & $model.Module {
            param($m)
            $m.Timer.Stop()
            if ($m.Run) { Close-AdDiscoveryGuiProcess $m.Run; $m.Run=$null }
            $m.Controls.CredentialPasswordInput.Clear()
            $m.Controls.CredentialUserInput.Clear()
        } $model
    }.GetNewClosure())
    $model.Initializing=$false
    Update-AdDiscoveryGuiPreview $model
    return $model
}

function Set-AdDiscoveryGuiCommonControls {
    param($Model,[hashtable]$Values)
    $Model.Initializing=$true
    $grid=$Model.Controls.CommonOptionsGrid
    $grid.Children.Clear(); $grid.RowDefinitions.Clear(); $grid.ColumnDefinitions.Clear()
    $left=New-Object Windows.Controls.ColumnDefinition; $left.Width=[Windows.GridLength]::new(170)
    $right=New-Object Windows.Controls.ColumnDefinition
    $grid.ColumnDefinitions.Add($left); $grid.ColumnDefinitions.Add($right)
    $Model.CommonControls=@{}
    $row=0
    foreach ($definition in @(Get-AdDiscoveryGuiCommonOptions -SupportsProgressAction $Model.Controls.EngineInput.SelectedItem.SupportsProgressAction)) {
        $rowDefinition=New-Object Windows.Controls.RowDefinition; $rowDefinition.Height=[Windows.GridLength]::Auto
        $grid.RowDefinitions.Add($rowDefinition)
        $label=New-Object Windows.Controls.TextBlock
        $label.Text='-' + $definition.Name; $label.VerticalAlignment='Center'; $label.Margin='0,0,8,8'; $label.ToolTip=$definition.Hint
        [Windows.Controls.Grid]::SetRow($label,$row); $grid.Children.Add($label) | Out-Null
        $control=switch ($definition.Kind) {
            Switch { New-Object Windows.Controls.CheckBox }
            Action { New-Object Windows.Controls.ComboBox }
            default { New-Object Windows.Controls.TextBox }
        }
        $control.Margin='0,0,0,8'; $control.ToolTip=$definition.Hint
        $value=if ($Values.ContainsKey($definition.Name)) { $Values[$definition.Name] } else { $null }
        if ($definition.Kind -eq 'Switch') {
            $control.IsChecked=(ConvertTo-AdAssessmentBoolean $value -Field $definition.Name) -eq $true
        } elseif ($definition.Kind -eq 'Action') {
            foreach ($item in @('(default)','Continue','SilentlyContinue','Stop','Ignore','Inquire','Break','Suspend')) { $control.Items.Add($item) | Out-Null }
            $control.SelectedItem=if ($value) { [string]$value } else { '(default)' }
        } else { $control.Text=[string]$value }
        [Windows.Controls.Grid]::SetRow($control,$row); [Windows.Controls.Grid]::SetColumn($control,1)
        $grid.Children.Add($control) | Out-Null
        $Model.CommonControls[$definition.Name]=[pscustomobject]@{Definition=$definition;Control=$control}
        $refresh={ & $Model.Module { param($m) Update-AdDiscoveryGuiPreview $m } $Model }.GetNewClosure()
        if ($definition.Kind -eq 'Switch') { $control.Add_Checked($refresh); $control.Add_Unchecked($refresh) }
        elseif ($definition.Kind -eq 'Action') { $control.Add_SelectionChanged($refresh) }
        else { $control.Add_TextChanged($refresh) }
        $row++
    }
    $Model.Initializing=$false
}

function Get-AdDiscoveryGuiSettings {
    param($Model)
    $c=$Model.Controls
    $common=@{}
    foreach ($name in $Model.CommonControls.Keys) {
        $entry=$Model.CommonControls[$name]
        $common[$name]=switch ($entry.Definition.Kind) {
            Switch { [bool]$entry.Control.IsChecked }
            Action { [string]$entry.Control.SelectedItem }
            default { $entry.Control.Text }
        }
    }
    return @{SchemaVersion=1;Environment=$c.EnvironmentInput.Text;OutputRoot=$c.OutputInput.Text;CustomerName=$c.CustomerInput.Text;
        Server=$c.ServerInput.Text;Domain=$c.DomainsInput.Text;IncludeSecurity=[bool]$c.SecurityInput.IsChecked;
        EngineId=$c.EngineInput.SelectedItem.Id;CommonParameters=$common;UseAlternateCredential=[bool]$c.AlternateCredentialInput.IsChecked}
}

function Set-AdDiscoveryGuiSettings {
    param($Model,[hashtable]$Settings)
    $engine=@($Model.Controls.EngineInput.ItemsSource | Where-Object Id -eq $Settings.EngineId)
    if ($engine.Count -ne 1) { throw "The settings require an unavailable PowerShell engine: $($Settings.EngineId)." }
    $null=ConvertTo-AdDiscoveryGuiParameters $Settings -SupportsProgressAction $engine[0].SupportsProgressAction
    $Model.Initializing=$true
    $c=$Model.Controls
    $c.EngineInput.SelectedItem=$engine[0]
    $c.EnvironmentInput.Text=[string]$Settings.Environment; $c.OutputInput.Text=[string]$Settings.OutputRoot
    $c.CustomerInput.Text=[string]$Settings.CustomerName; $c.ServerInput.Text=[string]$Settings.Server
    $c.DomainsInput.Text=@($Settings.Domain) -join [Environment]::NewLine
    $c.SecurityInput.IsChecked=(ConvertTo-AdAssessmentBoolean $Settings.IncludeSecurity -Field 'IncludeSecurity') -eq $true
    $c.CredentialUserInput.Clear(); $c.CredentialPasswordInput.Clear()
    $c.AlternateCredentialInput.IsChecked=$Settings.ContainsKey('UseAlternateCredential') -and (ConvertTo-AdAssessmentBoolean $Settings.UseAlternateCredential -Field 'UseAlternateCredential') -eq $true
    Set-AdDiscoveryGuiAuthenticationControls $Model
    Set-AdDiscoveryGuiCommonControls $Model $Settings.CommonParameters
    $Model.Initializing=$false
}

function Update-AdDiscoveryGuiPreview {
    param($Model)
    if ($Model.Initializing) { return }
    try {
        $parameters=ConvertTo-AdDiscoveryGuiParameters (Get-AdDiscoveryGuiSettings $Model) -SupportsProgressAction $Model.Controls.EngineInput.SelectedItem.SupportsProgressAction
        $Model.Controls.CommandPreview.Text=Format-AdDiscoveryGuiCommand $parameters $Model.ManifestPath -UseAlternateCredential:([bool]$Model.Controls.AlternateCredentialInput.IsChecked)
        if (-not $Model.Run) { $Model.Controls.FooterStatus.Text='Ready to collect inventory.' }
    } catch {
        $Model.Controls.CommandPreview.Text=$_.Exception.Message
        if (-not $Model.Run) { $Model.Controls.FooterStatus.Text=$_.Exception.Message }
    }
}

function Set-AdDiscoveryGuiState {
    param($Model,[string]$State,[string]$Message)
    $colors=switch ($State) { Complete { @('#DDF3E8','#16734A') }; Partial { @('#FFF0CF','#92600D') }; Failed { @('#FCE3E4','#AA2932') }; Stopped { @('#E7EAF0','#566477') }; default { @('#E4EDFC','#1764D8') } }
    $Model.Controls.StateText.Text=$State
    $Model.Controls.StateText.Foreground=$colors[1]; $Model.Controls.StateBadge.Background=$colors[0]
    $Model.Controls.FooterStatus.Text=$Message
}

function Set-AdDiscoveryGuiAuthenticationControls {
    param($Model)
    $alternate=[bool]$Model.Controls.AlternateCredentialInput.IsChecked
    $Model.Controls.CredentialsPanel.Visibility=if($alternate){'Visible'}else{'Collapsed'}
    if (-not $alternate) { $Model.Controls.CredentialPasswordInput.Clear(); $Model.Controls.CredentialUserInput.Clear() }
}

function Add-AdDiscoveryGuiOutput {
    param($Model,[string]$Text)
    if (-not $Text) { return }
    $box=$Model.Controls.LiveOutput
    $box.AppendText($Text)
    if ($box.Text.Length -gt 300000) { $box.Text=$box.Text.Substring($box.Text.Length-250000) }
    $box.ScrollToEnd()
}

function Set-AdDiscoveryGuiRunning {
    param($Model,[bool]$Running)
    foreach ($name in @('SettingsPanel','EngineInput','CredentialsPanel','AlternateCredentialInput','LoadSettingsButton','StartButton')) { $Model.Controls[$name].IsEnabled=-not $Running }
    $Model.Controls.StopButton.IsEnabled=$Running
}

function Update-AdDiscoveryGuiRun {
    param($Model)
    if (-not $Model.Run) { return }
    try {
        $run=$Model.Run
        foreach ($text in @(Read-AdDiscoveryGuiOutput $run)) { Add-AdDiscoveryGuiOutput $Model $text }
        $Model.Controls.ElapsedText.Text='Elapsed ' + ([datetime]::UtcNow-$run.StartedUtc).ToString('hh\:mm\:ss')
        $run.Process.Refresh()
        if (-not $run.Process.HasExited) { return }
        foreach ($text in @(Read-AdDiscoveryGuiOutput $run)) { Add-AdDiscoveryGuiOutput $Model $text }
        $state='Failed'; $result=$null; $message='The runner exited without a result. Review Live output and launcher logs.'
        if ($run.Stopped) { $state='Stopped'; $message='Stopped by the operator. Completed files remain; review the logs for unfinished operations.' }
        elseif (Test-Path -LiteralPath $run.ResultPath) {
            $envelope=Get-AdDiscoveryProcessEnvelope $run
            $state=[string]$envelope.State; $result=$envelope.Result
            if ($state -notin @('Complete','Partial','Failed')) { throw "Unexpected runner result '$state'." }
            if ($state -eq 'Complete' -and $run.Process.ExitCode -ne 0) { throw 'The runner returned a failure exit code with a complete result.' }
            $message=if ($state -eq 'Failed') { $envelope.ErrorMessage } elseif ($state -eq 'Partial') { 'Discovery finished with incomplete coverage. Review the issues and logs.' } else { 'Discovery completed successfully.' }
        }
        $Model.LastResult=$result
        $Model.Controls.ResultHeading.Text=$state + ' discovery'
        $Model.Controls.ResultSummary.Text=$message
        $issues=New-Object System.Collections.Generic.List[object]
        if ($result) {
            $Model.OpenRunPath=[string]$result.RunRoot
            $Model.Controls.ResultPath.Text=[string]$result.RunRoot
            $Model.Controls.ResultSummary.Text=$message + [Environment]::NewLine + ('Domains: {0}    Users: {1:N0}    Computers: {2:N0}    Groups: {3:N0}' -f $result.DomainCount,$result.UserCount,$result.ComputerCount,$result.GroupCount)
            foreach ($entry in @($result.FailedOperations)+@($result.IncompleteOperations)) { if ($entry) { $issues.Add($entry) } }
            if ($result.LoggingFailed) { $issues.Add([pscustomobject]@{Operation='Diagnostic logging';Status='FAIL';Message='Some diagnostics could not be saved. Review launcher output.'}) }
            foreach ($pair in @(@('OpenRunButton',$result.RunRoot),@('OpenLogButton',$result.LogPath),@('OpenStatusButton',$result.ExecutionStatusPath),@('OpenIndexButton',(Join-Path $result.RunRoot '99_manifest\Discovery.Index.json')))) {
                $Model.Controls[$pair[0]].IsEnabled=([bool]$pair[1] -and (Test-Path -LiteralPath $pair[1]))
            }
        } else {
            $Model.Controls.ResultPath.Text='Launcher logs: ' + $run.Folder
            $Model.OpenRunPath=$run.OutputRoot
            $Model.Controls.OpenRunButton.IsEnabled=([bool]$run.OutputRoot -and (Test-Path -LiteralPath $run.OutputRoot))
        }
        $Model.Controls.IssuesGrid.ItemsSource=$issues.ToArray()
        Set-AdDiscoveryGuiState $Model $state $message
        $Model.Controls.LiveStageText.Text=$message
        $Model.Controls.MainTabs.SelectedItem=$Model.Controls.ResultsTab
    } catch {
        Add-AdDiscoveryGuiOutput $Model ([Environment]::NewLine + '[Launcher] ' + $_.Exception.Message)
        Set-AdDiscoveryGuiState $Model Failed $_.Exception.Message
        $Model.Controls.ResultHeading.Text='Failed to read the run result'
        $Model.Controls.ResultSummary.Text=$_.Exception.Message
    } finally {
        if ($Model.Run -and ($Model.Run.Process.HasExited -or $Model.Controls.StateText.Text -eq 'Failed')) {
            $Model.Timer.Stop()
            Close-AdDiscoveryGuiProcess $Model.Run; $Model.Run=$null
            Set-AdDiscoveryGuiRunning $Model $false
        }
    }
}

function Invoke-AdDiscoveryGuiAction {
    param($Model,[string]$Action)
    try {
        $c=$Model.Controls
        switch ($Action) {
            Browse {
                $dialog=New-Object Windows.Forms.FolderBrowserDialog
                try { $dialog.Description='Select the discovery output root'; $dialog.SelectedPath=$c.OutputInput.Text; if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $c.OutputInput.Text=$dialog.SelectedPath } } finally { $dialog.Dispose() }
            }
            Copy {
                $parameters=ConvertTo-AdDiscoveryGuiParameters (Get-AdDiscoveryGuiSettings $Model) -SupportsProgressAction $c.EngineInput.SelectedItem.SupportsProgressAction
                [Windows.Clipboard]::SetText((Format-AdDiscoveryGuiCommand $parameters $Model.ManifestPath -UseAlternateCredential:([bool]$c.AlternateCredentialInput.IsChecked)))
            }
            Save {
                $settings=Get-AdDiscoveryGuiSettings $Model
                $null=ConvertTo-AdDiscoveryGuiParameters $settings -SupportsProgressAction $c.EngineInput.SelectedItem.SupportsProgressAction
                $dialog=New-Object Microsoft.Win32.SaveFileDialog
                $dialog.Filter='Discovery settings (*.json)|*.json'; $dialog.FileName='Discovery.settings.json'
                if ($dialog.ShowDialog($Model.Window)) { $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8 -ErrorAction Stop }
            }
            Load {
                $dialog=New-Object Microsoft.Win32.OpenFileDialog
                $dialog.Filter='Discovery settings (*.json)|*.json'
                if ($dialog.ShowDialog($Model.Window)) { Set-AdDiscoveryGuiSettings $Model (Import-AdDiscoveryGuiSettings $dialog.FileName); Update-AdDiscoveryGuiPreview $Model }
            }
            Start {
                if ($Model.Run) { return }
                $Model.Run=Start-AdDiscoveryGuiConfiguredRun $Model
                $Model.LaunchLogFolder=$Model.Run.Folder; $Model.LastResult=$null; $Model.OpenRunPath=''
                $c.LiveOutput.Clear(); $c.ResultPath.Clear(); $c.IssuesGrid.ItemsSource=@()
                foreach ($name in @('OpenRunButton','OpenLogButton','OpenStatusButton','OpenIndexButton')) { $c[$name].IsEnabled=$false }
                $c.LauncherLogsButton.IsEnabled=$true
                $c.ResultHeading.Text='Discovery running'; $c.ResultSummary.Text='Results will appear when collection finishes.'
                $c.MainTabs.SelectedItem=$c.OutputTab
                $c.LiveStageText.Text='Collecting inventory with ' + $c.EngineInput.SelectedItem.Name
                Set-AdDiscoveryGuiRunning $Model $true
                Set-AdDiscoveryGuiState $Model Running 'Discovery is running. You can monitor output or stop the run.'
                $Model.Timer.Start()
            }
            Stop { if ($Model.Run) { Stop-AdDiscoveryGuiProcess $Model.Run; $c.StopButton.IsEnabled=$false; $c.FooterStatus.Text='Stopping discovery...' } }
            default {
                $path=switch ($Action) {
                    LauncherLogs { $Model.LaunchLogFolder }
                    OpenRun { $Model.OpenRunPath }
                    OpenLog { $Model.LastResult.LogPath }
                    OpenStatus { $Model.LastResult.ExecutionStatusPath }
                    OpenIndex { Join-Path $Model.LastResult.RunRoot '99_manifest\Discovery.Index.json' }
                }
                if ($path -and (Test-Path -LiteralPath $path)) { Start-Process -FilePath explorer.exe -ArgumentList ('"' + $path + '"') -ErrorAction Stop | Out-Null }
            }
        }
    } catch {
        if ($Action -eq 'Start') {
            Set-AdDiscoveryGuiState $Model Failed ('Discovery could not start: ' + $_.Exception.Message)
            $Model.Controls.ResultHeading.Text='Discovery could not start'
            $Model.Controls.ResultSummary.Text=$_.Exception.Message
            $launchFolder=$_.Exception.Data['LaunchFolder']
            if ($launchFolder) { $Model.LaunchLogFolder=[string]$launchFolder; $Model.Controls.LauncherLogsButton.IsEnabled=$true }
        }
        [Windows.MessageBox]::Show($Model.Window,$_.Exception.Message,'Discovery launcher',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Error) | Out-Null
    }
}
