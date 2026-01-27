function New-AdAdmtIncludeFiles {
    [CmdletBinding()]
    param(
        # Object arrays from Get-AdAdUsers/Groups/Computers or similar
        [object[]]$Users,

        [object[]]$Groups,

        [object[]]$Computers,

        # Either a RunLayout object from New-AdAdmtRunLayout, or explicit paths
        [object]$RunLayout,

        [string]$UsersPath,

        [string]$GroupsPath,

        [string]$ComputersPath,

        # Optional rename maps (key=SourceName, value=hashtable with rename columns)
        [hashtable]$UserRenameMap,

        [hashtable]$GroupRenameMap,

        # Which property to use as SourceName (defaults match typical Get-AdAd* output)
        [string]$UserSourceNameProperty = 'SamAccountName',

        [string]$GroupSourceNameProperty = 'SamAccountName',

        [string]$ComputerSourceNameProperty = 'SamAccountName',

        # Rename column options
        [ValidateSet('TargetSAM', 'TargetRDN', 'TargetUPN')]
        [string[]]$UserRenameColumns = @('TargetSAM'),

        [ValidateSet('TargetSAM', 'TargetRDN')]
        [string[]]$GroupRenameColumns = @('TargetSAM'),

        [switch]$EnsureComputerTrailingDollar = $true,

        [switch]$Force
    )

    # Resolve paths from RunLayout or explicit parameters
    $userPath = if ($RunLayout -and $RunLayout.PSObject.Properties['UsersIncludePath']) {
        $RunLayout.UsersIncludePath
    } elseif ($UsersPath) {
        $UsersPath
    } else {
        $null
    }

    $groupPath = if ($RunLayout -and $RunLayout.PSObject.Properties['GroupsIncludePath']) {
        $RunLayout.GroupsIncludePath
    } elseif ($GroupsPath) {
        $GroupsPath
    } else {
        $null
    }

    $computerPath = if ($RunLayout -and $RunLayout.PSObject.Properties['ComputersIncludePath']) {
        $RunLayout.ComputersIncludePath
    } elseif ($ComputersPath) {
        $ComputersPath
    } else {
        $null
    }

    $results = [ordered]@{
        UsersFile      = $null
        GroupsFile     = $null
        ComputersFile  = $null
        UsersCount     = 0
        GroupsCount    = 0
        ComputersCount = 0
        Errors         = New-Object System.Collections.Generic.List[string]
    }

    # Generate Users include file
    if ($Users -and $Users.Count -gt 0) {
        if (-not $userPath) {
            $results.Errors.Add('Users provided but no path specified (RunLayout.UsersIncludePath or -UsersPath)')
        } else {
            try {
                $exportParams = @{
                    Users              = $Users
                    Path               = $userPath
                    SourceNameProperty = $UserSourceNameProperty
                    RenameColumns      = $UserRenameColumns
                    Force              = $Force
                }
                if ($UserRenameMap) { $exportParams['RenameMap'] = $UserRenameMap }

                $results.UsersFile = Export-AdAdmtIncludeFileUsers @exportParams
                $results.UsersCount = $Users.Count
            } catch {
                $results.Errors.Add("Users export failed: $($_.Exception.Message)")
            }
        }
    }

    # Generate Groups include file
    if ($Groups -and $Groups.Count -gt 0) {
        if (-not $groupPath) {
            $results.Errors.Add('Groups provided but no path specified (RunLayout.GroupsIncludePath or -GroupsPath)')
        } else {
            try {
                $exportParams = @{
                    Groups             = $Groups
                    Path               = $groupPath
                    SourceNameProperty = $GroupSourceNameProperty
                    RenameColumns      = $GroupRenameColumns
                    Force              = $Force
                }
                if ($GroupRenameMap) { $exportParams['RenameMap'] = $GroupRenameMap }

                $results.GroupsFile = Export-AdAdmtIncludeFileGroups @exportParams
                $results.GroupsCount = $Groups.Count
            } catch {
                $results.Errors.Add("Groups export failed: $($_.Exception.Message)")
            }
        }
    }

    # Generate Computers include file
    if ($Computers -and $Computers.Count -gt 0) {
        if (-not $computerPath) {
            $results.Errors.Add('Computers provided but no path specified (RunLayout.ComputersIncludePath or -ComputersPath)')
        } else {
            try {
                $exportParams = @{
                    Computers            = $Computers
                    Path                 = $computerPath
                    SourceNameProperty   = $ComputerSourceNameProperty
                    EnsureTrailingDollar = $EnsureComputerTrailingDollar
                    Force                = $Force
                }

                $results.ComputersFile = Export-AdAdmtIncludeFileComputers @exportParams
                $results.ComputersCount = $Computers.Count
            } catch {
                $results.Errors.Add("Computers export failed: $($_.Exception.Message)")
            }
        }
    }

    # Validate at least one file was generated
    if (-not $results.UsersFile -and -not $results.GroupsFile -and -not $results.ComputersFile) {
        if ($results.Errors.Count -eq 0) {
            $results.Errors.Add('No objects provided for export (Users, Groups, or Computers required)')
        }
    }

    return [pscustomobject]$results
}
