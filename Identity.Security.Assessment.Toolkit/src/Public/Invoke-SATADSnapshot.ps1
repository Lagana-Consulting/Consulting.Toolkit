function Invoke-SATADSnapshot {
    [CmdletBinding()]
    param (
        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$OutputRoot,

        [int]$StaleDays = 90,

        [switch]$IUnderstandThisIsIntrusive
    )

    Set-StrictMode -Version Latest

    $profileData = Read-AssessmentProfile -Profile $Profile
    $assessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    $logPath = Join-Path $assessmentPath 'assessment.log'
    $toolVersionsPath = Join-Path $assessmentPath 'tool_versions.txt'

    Write-SATLog -Message "Invoke-SATADSnapshot started. Profile=$Profile" -LogPath $logPath

    $adModule = Get-Module -ListAvailable -Name ActiveDirectory
    if (-not $adModule) {
        Write-Warning 'ActiveDirectory module not available. Creating empty artifacts.'
        Write-SATLog -Message 'ActiveDirectory module not available.' -LogPath $logPath
    } else {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        Add-Content -Path $toolVersionsPath -Value "ActiveDirectory: $($adModule.Version)"
    }

    $usersCsv = Join-Path $assessmentPath 'ad_users.csv'
    $groupsCsv = Join-Path $assessmentPath 'ad_groups.csv'
    $privCsv = Join-Path $assessmentPath 'privileged_groups.csv'
    $gpoCsv = Join-Path $assessmentPath 'gpo_summary.csv'
    $staleCsv = Join-Path $assessmentPath 'stale_computers.csv'

    $usersHeaders = @('SamAccountName', 'DisplayName', 'Enabled', 'LastLogonDate', 'PasswordLastSet', 'WhenCreated', 'SourceTool')
    $groupsHeaders = @('Name', 'SamAccountName', 'GroupCategory', 'GroupScope', 'MemberCount', 'SourceTool')
    $privHeaders = @('GroupName', 'MemberSamAccountName', 'MemberObjectClass', 'SourceTool')
    $gpoHeaders = @('Name', 'Id', 'Status', 'CreationTime', 'ModificationTime', 'SourceTool')
    $staleHeaders = @('Name', 'OperatingSystem', 'LastLogonDate', 'Enabled', 'PasswordLastSet', 'SourceTool')

    if (-not $adModule) {
        New-SATCsv -Path $usersCsv -Headers $usersHeaders
        New-SATCsv -Path $groupsCsv -Headers $groupsHeaders
        New-SATCsv -Path $privCsv -Headers $privHeaders
        New-SATCsv -Path $gpoCsv -Headers $gpoHeaders
        New-SATCsv -Path $staleCsv -Headers $staleHeaders
        return $assessmentPath
    }

    $users = Get-ADUser -Filter * -Properties DisplayName, Enabled, LastLogonDate, PasswordLastSet, WhenCreated |
    Select-Object SamAccountName, DisplayName, Enabled, LastLogonDate, PasswordLastSet, WhenCreated,
    @{ Name = 'SourceTool'; Expression = { 'ActiveDirectory' } }

    if ($users.Count -gt 0) {
        $users | Export-Csv -Path $usersCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-SATCsv -Path $usersCsv -Headers $usersHeaders
    }

    $groups = Get-ADGroup -Filter * -Properties GroupCategory, GroupScope |
    Select-Object Name, SamAccountName, GroupCategory, GroupScope,
    @{ Name = 'MemberCount'; Expression = { $null } },
    @{ Name = 'SourceTool'; Expression = { 'ActiveDirectory' } }

    if ($groups.Count -gt 0) {
        $groups | Export-Csv -Path $groupsCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-SATCsv -Path $groupsCsv -Headers $groupsHeaders
    }

    $privGroups = @('Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators', 'Account Operators', 'Backup Operators')
    $privMembers = @()
    foreach ($groupName in $privGroups) {
        $group = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
        if ($group) {
            $members = Get-ADGroupMember -Identity $group -Recursive -ErrorAction SilentlyContinue
            foreach ($member in $members) {
                $privMembers += [pscustomobject]@{
                    GroupName            = $groupName
                    MemberSamAccountName = $member.SamAccountName
                    MemberObjectClass    = $member.ObjectClass
                    SourceTool           = 'ActiveDirectory'
                }
            }
        }
    }

    if ($privMembers.Count -gt 0) {
        $privMembers | Export-Csv -Path $privCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-SATCsv -Path $privCsv -Headers $privHeaders
    }

    $gpoModule = Get-Module -ListAvailable -Name GroupPolicy
    if ($gpoModule) {
        Import-Module GroupPolicy -ErrorAction SilentlyContinue
        Add-Content -Path $toolVersionsPath -Value "GroupPolicy: $($gpoModule.Version)"
        $gpos = Get-GPO -All -ErrorAction SilentlyContinue |
        Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime |
        ForEach-Object {
            [pscustomobject]@{
                Name             = $_.DisplayName
                Id               = $_.Id
                Status           = $_.GpoStatus
                CreationTime     = $_.CreationTime
                ModificationTime = $_.ModificationTime
                SourceTool       = 'GroupPolicy'
            }
        }

        if ($gpos.Count -gt 0) {
            $gpos | Export-Csv -Path $gpoCsv -NoTypeInformation -Encoding UTF8
        } else {
            New-SATCsv -Path $gpoCsv -Headers $gpoHeaders
        }
    } else {
        Write-SATLog -Message 'GroupPolicy module not available.' -LogPath $logPath
        New-SATCsv -Path $gpoCsv -Headers $gpoHeaders
    }

    $staleCutoff = (Get-Date).AddDays(-$StaleDays)
    $staleComputers = Get-ADComputer -Filter * -Properties LastLogonDate, PasswordLastSet, OperatingSystem, Enabled |
    Where-Object { $_.LastLogonDate -lt $staleCutoff -or -not $_.LastLogonDate } |
    Select-Object Name, OperatingSystem, LastLogonDate, Enabled, PasswordLastSet,
    @{ Name = 'SourceTool'; Expression = { 'ActiveDirectory' } }

    if ($staleComputers.Count -gt 0) {
        $staleComputers | Export-Csv -Path $staleCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-SATCsv -Path $staleCsv -Headers $staleHeaders
    }

    Write-SATLog -Message "Invoke-SATADSnapshot completed. OutputPath=$assessmentPath" -LogPath $logPath
    return [pscustomobject]@{
        AssessmentPath = $assessmentPath
        Scope          = 'AD'
        EvidenceFiles  = @($usersCsv, $groupsCsv, $privCsv, $gpoCsv, $staleCsv)
        FindingIds     = @()
    }
}
