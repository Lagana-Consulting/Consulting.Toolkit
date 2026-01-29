function Invoke-AdCrossForestDuplicateCheck {
    <#
    .SYNOPSIS
    Performs cross-forest duplicate object analysis for migration planning.

    .DESCRIPTION
    Analyzes source and target AD environments for duplicate sAMAccountName, UPN, and mail attributes
    across forests. Useful for ADMT pre-migration validation. Can use a JSON configuration file or
    individual parameters.

    .PARAMETER ConfigPath
    Path to JSON configuration file containing SourceRunRoots, TargetRunRoot, and OutputRoot.
    Defaults to: C:\Users\PLagana\OneDrive - Quest\Documents\GitHub\Migration.Toolkit\src\Migration.Toolkit.Analysis\config\Anlaysis_MultiSource_Config.json

    .PARAMETER SourceRunRoots
    Array of source AD discovery output directories. Takes precedence over ConfigPath.

    .PARAMETER TargetRunRoot
    Target AD discovery output directory. Takes precedence over ConfigPath.

    .PARAMETER OutputRoot
    Directory where cross-forest duplicate report will be saved.
    If not provided, defaults to current directory with timestamp.

    .PARAMETER ExcludeBuiltIn
    Exclude built-in users, groups, and computer accounts (default: all built-in Microsoft AD objects).

    Excluded accounts include:
    - Users: Administrator, Guest, krbtgt, DefaultAccount, WDAGUtilityAccount
    - Admin groups: Domain Admins, Enterprise Admins, Schema Admins, Administrators
    - Service groups: DnsAdmins, DnsUpdateProxy, RAS and IAS Servers, Certificate Publishers
    - DC groups: Domain Controllers, Read-only Domain Controllers, Enterprise RODCs
    - Operational groups: Account Operators, Backup Operators, Print Operators, Server Operators
    - Infrastructure: Pre-Windows 2000 Compatible Access, Incoming Forest Trust Builders
    - Security: Protected Users, Key Admins, Enterprise Key Admins
    - Special: All other standard AD system groups

    Use this flag to focus on user-created duplicates rather than infrastructure noise.

    .PARAMETER PassThru
    Return the duplicate objects instead of only writing to CSV.

    .EXAMPLE
    # Use default config file
    Invoke-AdCrossForestDuplicateCheck

    # Use parameters
    Invoke-AdCrossForestDuplicateCheck `
      -SourceRunRoots 'C:\Reports\Source1', 'C:\Reports\Source2' `
      -TargetRunRoot 'C:\Reports\Target' `
      -OutputRoot 'C:\Reports\Analysis'

    # Exclude built-in accounts from analysis
    Invoke-AdCrossForestDuplicateCheck -ExcludeBuiltIn

    # Get duplicates for further processing (excluding built-in)
    $duplicates = Invoke-AdCrossForestDuplicateCheck -PassThru -ExcludeBuiltIn
    $duplicates | Where-Object { $_.Severity -eq 'High' } | Export-Csv conflicted.csv

    .OUTPUTS
    If -PassThru is specified: PSCustomObject array of duplicate conflicts
    Otherwise: File path to generated CSV report
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $false)]
        [ValidateScript({
                foreach ($p in $_) {
                    if (-not (Test-Path -LiteralPath $p -PathType Container)) { return $false }
                }
                return $true
            })]
        [string[]]$SourceRunRoots,

        [Parameter(Mandatory = $false)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$TargetRunRoot,

        [Parameter(Mandatory = $false)]
        [string]$OutputRoot,

        [Parameter(Mandatory = $false)]
        [switch]$ExcludeBuiltIn,

        [Parameter(Mandatory = $false)]
        [switch]$PassThru
    )

    $ErrorActionPreference = 'Stop'

    # ========================================
    # Resolve configuration
    # ========================================
    if (-not $ConfigPath) {
        $defaultConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\Anlaysis_MultiSource_Config.json'
        $ConfigPath = $defaultConfigPath
    }

    $config = $null
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
            Write-Verbose "Loaded config from: $ConfigPath"
        }
        catch {
            Write-Warning "Failed to parse config file: $($_.Exception.Message)"
            $config = $null
        }
    }
    else {
        Write-Verbose "Config file not found: $ConfigPath (will use parameters)"
    }

    # Apply parameters (override config)
    if ($PSBoundParameters.ContainsKey('SourceRunRoots') -and $SourceRunRoots.Count -gt 0) {
        $SourceRunRoot = $SourceRunRoots
        Write-Verbose "Using parameter SourceRunRoots (overriding config)"
    }
    else {
        $SourceRunRoot = $config.SourceRunRoots
    }

    if ($PSBoundParameters.ContainsKey('TargetRunRoot')) {
        # Already set
        Write-Verbose "Using parameter TargetRunRoot (overriding config)"
    }
    else {
        $TargetRunRoot = $config.TargetRunRoot
    }

    if ($PSBoundParameters.ContainsKey('OutputRoot')) {
        # Already set
    }
    else {
        $OutputRoot = $config.OutputRoot
    }

    # Validate required parameters
    if (-not $SourceRunRoot -or $SourceRunRoot.Count -eq 0) {
        throw "SourceRunRoots must be provided via parameters or config file"
    }
    if (-not $TargetRunRoot) {
        throw "TargetRunRoot must be provided via parameters or config file"
    }

    # Ensure all source roots exist
    foreach ($src in $SourceRunRoot) {
        if (-not (Test-Path -LiteralPath $src -PathType Container)) {
            throw "Source directory not found: $src"
        }
    }

    if (-not (Test-Path -LiteralPath $TargetRunRoot -PathType Container)) {
        throw "Target directory not found: $TargetRunRoot"
    }

    # Set default OutputRoot if not provided
    if (-not $OutputRoot) {
        $OutputRoot = Join-Path (Get-Location).Path "CrossForestDuplicateAnalysis_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }

    # Create output directory
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    $reportPath = Join-Path $OutputRoot "AD__Duplicate__Objects__Cross_Forest.csv"

    Write-Verbose "SourceRunRoots: $($SourceRunRoot -join ', ')"
    Write-Verbose "TargetRunRoot: $TargetRunRoot"
    Write-Verbose "OutputRoot: $OutputRoot"

    # ========================================
    # Load AD objects from discovery output
    # ========================================
    Write-Verbose "Loading source AD objects..."
    $sourceUsers = @()
    $sourceGroups = @()
    $sourceComputers = @()

    foreach ($srcRoot in $SourceRunRoot) {
        $sourceDomainDir = Join-Path $srcRoot '20_domains'
        if (Test-Path -LiteralPath $sourceDomainDir) {
            Get-ChildItem -Path $sourceDomainDir -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
                $domainFolder = $_.FullName

                # Users
                $userPattern = Join-Path $domainFolder 'AD__Domain__Identity__Users__*.csv'
                Get-ChildItem -Path $userPattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $sourceUsers += Import-Csv -Path $_.FullName -ErrorAction SilentlyContinue
                }

                # Groups
                $groupPattern = Join-Path $domainFolder 'AD__Domain__Identity__Groups__*.csv'
                Get-ChildItem -Path $groupPattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $sourceGroups += Import-Csv -Path $_.FullName -ErrorAction SilentlyContinue
                }

                # Computers
                $compPattern = Join-Path $domainFolder 'AD__Domain__Identity__ComputersAll__*.csv'
                Get-ChildItem -Path $compPattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $sourceComputers += Import-Csv -Path $_.FullName -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Write-Verbose "Loaded source: $($sourceUsers.Count) users, $($sourceGroups.Count) groups, $($sourceComputers.Count) computers"

    Write-Verbose "Loading target AD objects..."
    $targetUsers = @()
    $targetGroups = @()
    $targetComputers = @()

    $targetDomainDir = Join-Path $TargetRunRoot '20_domains'
    if (Test-Path -LiteralPath $targetDomainDir) {
        Get-ChildItem -Path $targetDomainDir -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
            $domainFolder = $_.FullName

            # Users
            $userPattern = Join-Path $domainFolder 'AD__Domain__Identity__Users__*.csv'
            Get-ChildItem -Path $userPattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                $targetUsers += Import-Csv -Path $_.FullName -ErrorAction SilentlyContinue
            }

            # Groups
            $groupPattern = Join-Path $domainFolder 'AD__Domain__Identity__Groups__*.csv'
            Get-ChildItem -Path $groupPattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                $targetGroups += Import-Csv -Path $_.FullName -ErrorAction SilentlyContinue
            }

            # Computers
            $compPattern = Join-Path $domainFolder 'AD__Domain__Identity__ComputersAll__*.csv'
            Get-ChildItem -Path $compPattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                $targetComputers += Import-Csv -Path $_.FullName -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Verbose "Loaded target: $($targetUsers.Count) users, $($targetGroups.Count) groups, $($targetComputers.Count) computers"

    # Tag environment
    $sourceUsers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
    $sourceGroups | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
    $sourceComputers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Source' -Force }
    $targetUsers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }
    $targetGroups | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }
    $targetComputers | ForEach-Object { $_ | Add-Member -NotePropertyName Environment -NotePropertyValue 'Target' -Force }

    # Combine
    $allUsers = @($sourceUsers) + @($targetUsers)
    $allGroups = @($sourceGroups) + @($targetGroups)
    $allComputers = @($sourceComputers) + @($targetComputers)

    # ========================================
    # Run duplicate check
    # ========================================
    Write-Verbose "Running duplicate analysis..."
    $crossForestDuplicates = @()

    if ($allUsers.Count -gt 0 -or $allGroups.Count -gt 0 -or $allComputers.Count -gt 0) {
        $dupParams = @{
            AllUsers     = @($allUsers)
            AllGroups    = @($allGroups)
            AllComputers = @($allComputers)
        }

        if ($ExcludeBuiltIn) { $dupParams['ExcludeBuiltIn'] = $true }
        $duplicates = Get-AdDuplicateObjectsCrossForest @dupParams

        # Filter to cross-forest only (where ConflictingDomains contains multiple entries)
        $crossForestDuplicates = @($duplicates | Where-Object {
                ($_.ConflictingDomains -match ';') -or
                ($_.ConflictCount -gt 1)
            })

        Write-Verbose "Found $($crossForestDuplicates.Count) cross-forest conflicts"

        # Export results if not PassThru
        if (-not $PassThru) {
            if ($crossForestDuplicates.Count -gt 0) {
                $exportColumns = $crossForestDuplicates[0].PSObject.Properties.Name | Where-Object { $_ -notin @('Severity', 'Recommendations', 'Recommendation') }
                $crossForestDuplicates |
                Select-Object -Property $exportColumns |
                Export-Csv -Path $reportPath -NoTypeInformation -Force
                Write-Host "Cross-forest duplicates exported: $reportPath ($($crossForestDuplicates.Count) conflicts)" -ForegroundColor Yellow
            }
            else {
                Write-Host "No cross-forest duplicate objects detected" -ForegroundColor Green
            }
        }
    }
    else {
        Write-Warning "No user/group/computer data found to analyze"
    }

    # ========================================
    # Return results
    # ========================================
    if ($PassThru) {
        return $crossForestDuplicates
    }
    else {
        return @{
            ReportPath     = if ($crossForestDuplicates.Count -gt 0) { $reportPath } else { $null }
            ConflictCount  = $crossForestDuplicates.Count
            Conflicts      = $crossForestDuplicates
            UserConflicts  = @($crossForestDuplicates | Where-Object { $_.ObjectClasses -match 'user' }).Count
            GroupConflicts = @($crossForestDuplicates | Where-Object { $_.ObjectClasses -match 'group' }).Count
            CompConflicts  = @($crossForestDuplicates | Where-Object { $_.ObjectClasses -match 'computer' }).Count
        }
    }
}
