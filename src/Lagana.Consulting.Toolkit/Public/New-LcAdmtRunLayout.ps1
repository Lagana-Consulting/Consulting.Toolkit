function New-LcAdmtRunLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputRoot,

        [string]$Prefix = 'ADMT',

        [datetime]$Now = (Get-Date),

        [switch]$CreateLog,

        [string]$LogPrefix = 'admt'
    )

    $root = Resolve-LcPath -Path $OutputRoot
    New-LcDirectory -Path $root | Out-Null

    $stamp = $Now.ToString('yyyyMMdd-HHmmss')
    $runFolderName = "{0}_{1}" -f $Prefix, $stamp
    $runRoot = Join-Path $root $runFolderName
    New-LcDirectory -Path $runRoot | Out-Null

    $includeDir = Join-Path $runRoot 'include'
    New-LcDirectory -Path $includeDir | Out-Null

    $optionsDir = Join-Path $runRoot 'options'
    New-LcDirectory -Path $optionsDir | Out-Null

    $logsDir = Join-Path $runRoot 'logs'
    New-LcDirectory -Path $logsDir | Out-Null

    $logPath = $null
    if ($CreateLog) {
        $logPath = New-LcLog -Folder $logsDir -Prefix $LogPrefix
        Write-LcLog -Path $logPath -Level INFO -Message ("ADMT run layout created. RunRoot={0}" -f $runRoot)
    }

    $defaultUsersInclude = Join-Path $includeDir 'ADMT_Include_Users.csv'
    $defaultGroupsInclude = Join-Path $includeDir 'ADMT_Include_Groups.csv'
    $defaultComputersInclude = Join-Path $includeDir 'ADMT_Include_Computers.csv'
    $defaultOptionFile = Join-Path $optionsDir 'ADMT_Options.ini'

    [pscustomobject]@{
        OutputRoot           = $root
        RunRoot              = $runRoot
        IncludeDir           = $includeDir
        OptionsDir           = $optionsDir
        LogsDir              = $logsDir
        LogPath              = $logPath
        UsersIncludePath     = $defaultUsersInclude
        GroupsIncludePath    = $defaultGroupsInclude
        ComputersIncludePath = $defaultComputersInclude
        OptionFilePath       = $defaultOptionFile
        Prefix               = $Prefix
        Stamp                = $stamp
        Now                  = $Now
    }
}
