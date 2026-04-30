function Export-AdPowerBiDataset {
    <#
    .SYNOPSIS
    Exports curated CSV tables for Power BI Desktop from discovery and analysis outputs.

    .DESCRIPTION
    Reads one or more Consulting.Toolkit.Discovery run folders and produces a set of
    Power BI-friendly CSV tables with stable keys and summary facts.

    Optional workspace inputs from Invoke-AdDiscoveryAnalysis are also included when
    available, such as identity collisions and password policy diffs.

    .PARAMETER RunRoot
    One or more discovery run roots to include in the exported dataset.

    .PARAMETER WorkspaceRoot
    Optional analysis workspace root produced by Invoke-AdDiscoveryAnalysis.

    .PARAMETER OutputRoot
    Folder where curated CSV tables will be written.

    .EXAMPLE
    Export-AdPowerBiDataset `
      -RunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
      -OutputRoot "F:\Shared\PowerBI\ADDataset"

    .EXAMPLE
    Export-AdPowerBiDataset `
      -RunRoot @("F:\Shared\AD_source_20260423-082040","F:\Shared\AD_target_20260423-090000") `
      -WorkspaceRoot "F:\Shared\AnalysisWorkspace" `
      -OutputRoot "F:\Shared\PowerBI\ADDataset"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$RunRoot,

        [string]$WorkspaceRoot,

        [string]$OutputRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $RunRoot = @($RunRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($RunRoot.Count -eq 0) {
        throw "Provide at least one RunRoot."
    }

    foreach ($path in $RunRoot) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Run root not found: $path"
        }
    }

    if ($WorkspaceRoot -and -not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
        throw "Workspace root not found: $WorkspaceRoot"
    }

    if (-not $OutputRoot) {
        $timestamp = Get-AdTimestamp -Format File
        $OutputRoot = Join-Path (Get-Location).Path "PowerBI_Dataset_$timestamp"
    }

    if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }

    function Write-CsvTable {
        param(
            [Parameter(Mandatory)][string]$Name,
            [AllowEmptyCollection()][object[]]$Rows = @()
        )

        if (@($Rows).Count -eq 0) { return $null }

        $path = Join-Path $OutputRoot "$Name.csv"
        $Rows | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8 -Force
        return $path
    }

    $dimRuns = New-Object System.Collections.Generic.List[object]
    $dimDomains = New-Object System.Collections.Generic.List[object]
    $factRunSummary = New-Object System.Collections.Generic.List[object]
    $factDomainSummary = New-Object System.Collections.Generic.List[object]
    $factRiskSummary = New-Object System.Collections.Generic.List[object]
    $factPasswordPolicy = New-Object System.Collections.Generic.List[object]
    $factTrusts = New-Object System.Collections.Generic.List[object]
    $factGpoInventory = New-Object System.Collections.Generic.List[object]
    $factDomainControllers = New-Object System.Collections.Generic.List[object]
    $factPrivilegedAccounts = New-Object System.Collections.Generic.List[object]
    $factServiceAccountCandidates = New-Object System.Collections.Generic.List[object]

    foreach ($runPath in $RunRoot) {
        $runData = Get-AdDiscoveryRunSummary -RunRoot $runPath
        $index = Get-AdDiscoveryIndexData -RunRoot $runPath
        $runName = Split-Path -Leaf $runPath
        $environment = if ($index -and $index.environment) { [string]$index.environment } else { 'Unknown' }
        $runKey = "{0}|{1}" -f $environment, $runName

        $dimRuns.Add([pscustomobject]@{
                RunKey         = $runKey
                RunName        = $runName
                RunRoot        = $runPath
                Environment    = $environment
                CustomerName   = if ($index -and $index.customerName) { [string]$index.customerName } else { '' }
                GeneratedAtUtc = if ($runData.GeneratedAtUtc) { $runData.GeneratedAtUtc } else { $runData.Summary.RunTimestamp }
                ForestName     = $runData.Summary.ForestName
                ForestRootDomain = $runData.Summary.ForestRootDomain
                DomainsCount   = $runData.Summary.DomainsCount
            })

        $summary = $runData.Summary
        $factRunSummary.Add([pscustomobject]@{
                RunKey                        = $runKey
                RunName                       = $runName
                Environment                   = $environment
                RunTimestamp                  = $summary.RunTimestamp
                ForestName                    = $summary.ForestName
                ForestRootDomain              = $summary.ForestRootDomain
                DomainsCount                  = $summary.DomainsCount
                TrustCount                    = $summary.TrustCount
                UsersTotal                    = $summary.UsersTotal
                GroupsTotal                   = $summary.GroupsTotal
                ComputersTotal                = $summary.ComputersTotal
                UsersStaleCount               = $summary.UsersStaleCount
                UsersStalePct                 = $summary.UsersStalePct
                ComputersStaleCount           = $summary.ComputersStaleCount
                ComputersStalePct             = $summary.ComputersStalePct
                UsersSIDHistoryCount          = $summary.UsersSIDHistoryCount
                UsersSIDHistoryPct            = $summary.UsersSIDHistoryPct
                UsersNonRoutableUPNCount      = $summary.UsersNonRoutableUPNCount
                UsersNonRoutableUPNPct        = $summary.UsersNonRoutableUPNPct
                ObjectsRC4OnlyCount           = $summary.ObjectsRC4OnlyCount
                ObjectsRC4OnlyPct             = $summary.ObjectsRC4OnlyPct
                PrivilegedAccountsCount       = $summary.PrivilegedAccountsCount
                WeakPasswordPoliciesCount     = $summary.WeakPasswordPoliciesCount
                DisabledUsersCount            = $summary.DisabledUsersCount
                DisabledComputersCount        = $summary.DisabledComputersCount
                AdminSdHolderImpactCount      = $summary.AdminSdHolderImpactCount
                AsrepRoastableUsersCount      = $summary.AsrepRoastableUsersCount
                UnconstrainedDelegationCount  = $summary.UnconstrainedDelegationCount
                ProtectedUsersCount           = $summary.ProtectedUsersCount
                ServiceAccountCandidatesCount = $summary.ServiceAccountCandidatesCount
                DomainControllerCount         = $summary.DomainControllerCount
                GpoCount                      = $summary.GpoCount
                OuCount                       = $summary.OuCount
                SpnCount                      = $summary.SpnCount
                FGPPCount                     = $summary.FGPPCount
                UpnSuffixCount                = $summary.UpnSuffixCount
                SiteCount                     = $summary.SiteCount
                SiteLinkCount                 = $summary.SiteLinkCount
                AdcsEnterpriseCaCount         = $summary.AdcsEnterpriseCaCount
            })

        foreach ($domainInfo in @($runData.DomainSummaries)) {
            $domain = $domainInfo.Domain
            $domainSummary = $domainInfo.Summary
            $runDomainKey = "{0}|{1}" -f $runKey, $domain

            $dimDomains.Add([pscustomobject]@{
                    RunDomainKey      = $runDomainKey
                    RunKey            = $runKey
                    RunName           = $runName
                    Environment       = $environment
                    DomainFqdn        = $domain
                    ForestName        = $summary.ForestName
                    ForestRootDomain  = $summary.ForestRootDomain
                })

            $factDomainSummary.Add([pscustomobject]@{
                    RunDomainKey                 = $runDomainKey
                    RunKey                       = $runKey
                    RunName                      = $runName
                    Environment                  = $environment
                    DomainFqdn                   = $domain
                    UsersTotal                   = $domainSummary.UsersTotal
                    GroupsTotal                  = $domainSummary.GroupsTotal
                    ComputersTotal               = $domainSummary.ComputersTotal
                    SpnCount                     = $domainSummary.SpnCount
                    OuCount                      = $domainSummary.OuCount
                    GpoCount                     = $domainSummary.GpoCount
                    DomainControllerCount        = $domainSummary.DomainControllerCount
                    ServiceAccountCandidatesCount = $domainSummary.ServiceAccountCandidatesCount
                    PrivilegedAccountsCount      = $domainSummary.PrivilegedAccountsCount
                    UsersStaleCount              = $domainSummary.UsersStaleCount
                    UsersStalePct                = $domainSummary.UsersStalePct
                    ComputersStaleCount          = $domainSummary.ComputersStaleCount
                    ComputersStalePct            = $domainSummary.ComputersStalePct
                    DisabledUsersCount           = $domainSummary.DisabledUsersCount
                    DisabledComputersCount       = $domainSummary.DisabledComputersCount
                    UsersNonRoutableUPNCount     = $domainSummary.UsersNonRoutableUPNCount
                    UsersSidHistoryCount         = $domainSummary.UsersSidHistoryCount
                    AdminSdHolderImpactCount     = $domainSummary.AdminSdHolderImpactCount
                    AsrepRoastableUsersCount     = $domainSummary.AsrepRoastableUsersCount
                    UnconstrainedDelegationCount = $domainSummary.UnconstrainedDelegationCount
                    ProtectedUsersCount          = $domainSummary.ProtectedUsersCount
                    WeakPasswordPoliciesCount    = $domainSummary.WeakPasswordPoliciesCount
                    FGPPCount                    = $domainSummary.FGPPCount
                })

            if ($domainSummary.PasswordPolicy) {
                $policy = $domainSummary.PasswordPolicy
                $factPasswordPolicy.Add([pscustomobject]@{
                        RunDomainKey                     = $runDomainKey
                        RunKey                           = $runKey
                        RunName                          = $runName
                        Environment                      = $environment
                        DomainFqdn                       = $domain
                        ComplexityEnabled                = $policy.ComplexityEnabled
                        MinPasswordLength                = $policy.MinPasswordLength
                        PasswordHistoryCount             = $policy.PasswordHistoryCount
                        MinPasswordAgeDays               = $policy.MinPasswordAgeDays
                        MaxPasswordAgeDays               = $policy.MaxPasswordAgeDays
                        LockoutThreshold                 = $policy.LockoutThreshold
                        LockoutDurationMinutes           = $policy.LockoutDurationMinutes
                        LockoutObservationWindowMinutes  = $policy.LockoutObservationWindowMinutes
                        ReversibleEncryptionEnabled      = $policy.ReversibleEncryptionEnabled
                    })
            }
        }

        foreach ($risk in @($runData.RiskSummary)) {
            $factRiskSummary.Add([pscustomobject]@{
                    RunKey         = $runKey
                    RunName        = $runName
                    Environment    = $environment
                    ForestName     = $summary.ForestName
                    Flag           = $risk.Flag
                    Severity       = $risk.Severity
                    Count          = $risk.Count
                    Description    = $risk.Description
                    Recommendation = $risk.Recommendation
                })
        }

        foreach ($trust in @($runData.Trusts)) {
            $factTrusts.Add([pscustomobject]@{
                    RunKey                 = $runKey
                    RunName                = $runName
                    Environment            = $environment
                    ForestName             = $summary.ForestName
                    Name                   = $trust.Name
                    Source                 = $trust.Source
                    Target                 = $trust.Target
                    Direction              = $trust.Direction
                    TrustType              = $trust.TrustType
                    ForestTransitive       = $trust.ForestTransitive
                    SelectiveAuthentication = $trust.SelectiveAuthentication
                    SIDFilteringForestAware = $trust.SIDFilteringForestAware
                    SIDFilteringQuarantined = $trust.SIDFilteringQuarantined
                    UsesAESKeys            = $trust.UsesAESKeys
                    UsesRC4Encryption      = $trust.UsesRC4Encryption
                })
        }

        foreach ($domainFolder in @(Get-AdDiscoveryDomainFolders -RunRoot $runPath)) {
            $domain = $domainFolder.Name -replace '^Domain-', ''
            $runDomainKey = "{0}|{1}" -f $runKey, $domain

            foreach ($row in @(Get-AdDiscoveryFirstCsv -Directory $domainFolder.FullName -Patterns @('*__GPO__Inventory__*.csv'))) {
                $factGpoInventory.Add([pscustomobject]@{
                        RunDomainKey      = $runDomainKey
                        RunKey            = $runKey
                        RunName           = $runName
                        Environment       = $environment
                        DomainFqdn        = $domain
                        DisplayName       = $row.DisplayName
                        Id                = $row.Id
                        Owner             = $row.Owner
                        CreationTime      = $row.CreationTime
                        ModificationTime  = $row.ModificationTime
                        GpoStatus         = $row.GpoStatus
                        Description       = $row.Description
                        WmiFilter         = $row.WmiFilter
                    })
            }

            foreach ($row in @(Get-AdDiscoveryFirstCsv -Directory $domainFolder.FullName -Patterns @('*__Infrastructure__DomainControllers__*.csv'))) {
                $factDomainControllers.Add([pscustomobject]@{
                        RunDomainKey      = $runDomainKey
                        RunKey            = $runKey
                        RunName           = $runName
                        Environment       = $environment
                        DomainFqdn        = $domain
                        HostName          = $row.HostName
                        Name              = $row.Name
                        Site              = $row.Site
                        IPv4Address       = $row.IPv4Address
                        OperatingSystem   = $row.OperatingSystem
                        IsGlobalCatalog   = $row.IsGlobalCatalog
                        IsReadOnly        = $row.IsReadOnly
                        IsPdc             = $row.IsPdc
                        IsEnabled         = $row.IsEnabled
                    })
            }

            foreach ($row in @(Get-AdDiscoveryFirstCsv -Directory $domainFolder.FullName -Patterns @('*__Security__PrivilegedAccounts__*.csv'))) {
                $factPrivilegedAccounts.Add([pscustomobject]@{
                        RunDomainKey       = $runDomainKey
                        RunKey             = $runKey
                        RunName            = $runName
                        Environment        = $environment
                        DomainFqdn         = $domain
                        SamAccountName     = $row.SamAccountName
                        DistinguishedName  = $row.DistinguishedName
                        InPrivGroups       = $row.InPrivGroups
                        PrivGroups         = $row.PrivGroups
                        AdminCount         = $row.AdminCount
                    })
            }

            foreach ($row in @(Get-AdDiscoveryFirstCsv -Directory $domainFolder.FullName -Patterns @('*__Identity__ServiceAccountCandidates__*.csv'))) {
                $candidateName = if ($row.PSObject.Properties['Name']) { $row.Name } else { $row.SamAccountName }
                $candidateDn = if ($row.PSObject.Properties['DistinguishedName']) { $row.DistinguishedName } else { $null }
                $candidateSpn = if ($row.PSObject.Properties['ServicePrincipalName']) { $row.ServicePrincipalName } elseif ($row.PSObject.Properties['SPNCount']) { $row.SPNCount } else { $null }
                $factServiceAccountCandidates.Add([pscustomobject]@{
                        RunDomainKey         = $runDomainKey
                        RunKey               = $runKey
                        RunName              = $runName
                        Environment          = $environment
                        DomainFqdn           = $domain
                        SamAccountName       = $row.SamAccountName
                        Name                 = $candidateName
                        DistinguishedName    = $candidateDn
                        ServicePrincipalName = $candidateSpn
                        Enabled              = if ($row.PSObject.Properties['Enabled']) { $row.Enabled } else { $null }
                        UserPrincipalName    = if ($row.PSObject.Properties['UserPrincipalName']) { $row.UserPrincipalName } else { $null }
                        HeuristicFlags       = if ($row.PSObject.Properties['HeuristicFlags']) { $row.HeuristicFlags } else { $null }
                        PasswordAgeDays      = if ($row.PSObject.Properties['PasswordAgeDays']) { $row.PasswordAgeDays } else { $null }
                        LastLogonDays        = if ($row.PSObject.Properties['LastLogonDays']) { $row.LastLogonDays } else { $null }
                        Description          = $row.Description
                    })
            }
        }
    }

    $tableManifest = New-Object System.Collections.Generic.List[object]
    $exportTables = @(
        [pscustomobject]@{ Name = 'DimRun'; Rows = $dimRuns.ToArray() },
        [pscustomobject]@{ Name = 'DimDomain'; Rows = $dimDomains.ToArray() },
        [pscustomobject]@{ Name = 'FactRunSummary'; Rows = $factRunSummary.ToArray() },
        [pscustomobject]@{ Name = 'FactDomainSummary'; Rows = $factDomainSummary.ToArray() },
        [pscustomobject]@{ Name = 'FactRiskSummary'; Rows = $factRiskSummary.ToArray() },
        [pscustomobject]@{ Name = 'FactPasswordPolicy'; Rows = $factPasswordPolicy.ToArray() },
        [pscustomobject]@{ Name = 'FactTrusts'; Rows = $factTrusts.ToArray() },
        [pscustomobject]@{ Name = 'FactGpoInventory'; Rows = $factGpoInventory.ToArray() },
        [pscustomobject]@{ Name = 'FactDomainControllers'; Rows = $factDomainControllers.ToArray() },
        [pscustomobject]@{ Name = 'FactPrivilegedAccounts'; Rows = $factPrivilegedAccounts.ToArray() },
        [pscustomobject]@{ Name = 'FactServiceAccountCandidates'; Rows = $factServiceAccountCandidates.ToArray() }
    )

    foreach ($entry in $exportTables) {
        $path = Write-CsvTable -Name $entry.Name -Rows $entry.Rows
        if ($path) {
            $tableManifest.Add([pscustomobject]@{
                    Name  = $entry.Name
                    Path  = $path
                    Rows  = @($entry.Rows).Count
                    Type  = 'Curated'
                })
        }
    }

    if ($WorkspaceRoot) {
        $workspaceRunsPath = Join-Path $WorkspaceRoot '99_manifest\Workspace__Runs__Workspace.json'
        $identityCollisionsPath = Join-Path $WorkspaceRoot '30_analysis\cross_run\AD__CrossRun__IdentityCollisions.csv'
        $passwordPolicyDiffPath = Join-Path $WorkspaceRoot '30_analysis\cross_run\AD__CrossRun__PasswordPolicyDiff.csv'

        if (Test-Path -LiteralPath $workspaceRunsPath -PathType Leaf) {
            $workspaceRuns = Get-Content -LiteralPath $workspaceRunsPath -Raw | ConvertFrom-Json
            $rows = @($workspaceRuns.runs)
            $path = Write-CsvTable -Name 'FactWorkspaceRuns' -Rows $rows
            if ($path) {
                $tableManifest.Add([pscustomobject]@{
                        Name = 'FactWorkspaceRuns'
                        Path = $path
                        Rows = $rows.Count
                        Type = 'Workspace'
                    })
            }
        }

        if (Test-Path -LiteralPath $identityCollisionsPath -PathType Leaf) {
            $rows = Import-AdAnalysisCsvSafe -Path $identityCollisionsPath
            $path = Write-CsvTable -Name 'FactIdentityCollisions' -Rows $rows
            if ($path) {
                $tableManifest.Add([pscustomobject]@{
                        Name = 'FactIdentityCollisions'
                        Path = $path
                        Rows = @($rows).Count
                        Type = 'Workspace'
                    })
            }
        }

        if (Test-Path -LiteralPath $passwordPolicyDiffPath -PathType Leaf) {
            $rows = Import-AdAnalysisCsvSafe -Path $passwordPolicyDiffPath
            $path = Write-CsvTable -Name 'FactPasswordPolicyDiff' -Rows $rows
            if ($path) {
                $tableManifest.Add([pscustomobject]@{
                        Name = 'FactPasswordPolicyDiff'
                        Path = $path
                        Rows = @($rows).Count
                        Type = 'Workspace'
                    })
            }
        }
    }

    $manifestPath = Join-Path $OutputRoot 'DatasetManifest.json'
    [pscustomobject]@{
        generatedAtUtc = (Get-AdTimestamp -Format Iso)
        outputRoot     = $OutputRoot
        runCount       = $RunRoot.Count
        hasWorkspace   = [bool]$WorkspaceRoot
        tables         = $tableManifest.ToArray()
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    return [pscustomobject]@{
        OutputRoot    = $OutputRoot
        ManifestPath  = $manifestPath
        TablesWritten = $tableManifest.Count
        Tables        = $tableManifest.ToArray()
    }
}
