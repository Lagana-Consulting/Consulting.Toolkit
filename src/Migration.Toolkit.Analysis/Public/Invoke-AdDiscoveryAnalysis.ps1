<#
Invoke-AdDiscoveryAnalysis (Workspace Engine)
===========================================
- Supports:
  - One run only (source OR target)
  - Multiple source runs
  - Optional target run
- Reads each run's manifest index from:
  - 99_manifest\Discovery.Index.json (current Consulting.Toolkit.Discovery)
  - 99_manifest\Discovery__Index__Run.json (legacy)
  Falls back to file scan only when an index is not available.
- Produces:
  - <WorkspaceRoot>\30_analysis\cross_run\AD__CrossRun__IdentityCollisions.csv
  - <WorkspaceRoot>\30_analysis\cross_run\AD__CrossRun__PasswordPolicyDiff.csv
  - <WorkspaceRoot>\99_manifest\Workspace__Index__Workspace.json
  - <WorkspaceRoot>\99_manifest\Workspace__Runs__Workspace.json

No HTML. No “assessment engine”. No live AD queries. Pure offline analysis.

How you run it:

# Sources + Target
Invoke-AdDiscoveryAnalysis `
  -SourceRunRoot @("C:\Discovery\AD_contoso_source_20260215_090000","C:\Discovery\AD_fabrikam_source_20260215_091500") `
  -TargetRunRoot "C:\Discovery\AD_target_20260215_093000" `
  -WorkspaceRoot "C:\AnalysisWorkspaces\Contoso_20260216"

# Single run only (source-only OR target-only)
Invoke-AdDiscoveryAnalysis -SourceRunRoot "C:\Discovery\AD_contoso_source_20260215_090000"

# If you want source-vs-source password policy diffs (pairwise):
Invoke-AdDiscoveryAnalysis -SourceRunRoot @("C:\Discovery\F1","C:\Discovery\F2") -IncludeSourceVsSource

#>

function Invoke-AdDiscoveryAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'Manual')]
        [string[]]$SourceRunRoot,

        [Parameter(ParameterSetName = 'Manual')]
        [string]$TargetRunRoot,

        [Parameter(ParameterSetName = 'Config')]
        [string]$ConfigFile,

        [string]$WorkspaceRoot,

        # Cross-run collision config
        [string[]]$CollisionKeysUser = @('SamAccountName', 'UserPrincipalName', 'Mail', 'ProxyAddresses', 'ServicePrincipalName'),
        [string[]]$CollisionKeysGroup = @('SamAccountName', 'Mail', 'ProxyAddresses'),
        [string[]]$CollisionKeysComputer = @('Name', 'DnsHostName', 'ServicePrincipalName'),

        [switch]$IncludeSourceVsSource,
        [switch]$WhatIf
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # ---------------------------
    # Load config (optional)
    # ---------------------------
    if ($PSCmdlet.ParameterSetName -eq 'Config') {
        if (-not (Test-Path -LiteralPath $ConfigFile)) { throw "Config not found: $ConfigFile" }
        $cfg = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json

        $SourceRunRoot = @()
        if ($cfg.PSObject.Properties['SourceRunRoots']) { $SourceRunRoot = @($cfg.SourceRunRoots) }
        elseif ($cfg.PSObject.Properties['SourceRunRoot']) { $SourceRunRoot = @($cfg.SourceRunRoot) }

        $TargetRunRoot = $cfg.TargetRunRoot
        if (-not $WorkspaceRoot -and $cfg.PSObject.Properties['WorkspaceRoot']) { $WorkspaceRoot = $cfg.WorkspaceRoot }

        if ($cfg.PSObject.Properties['IncludeSourceVsSource']) { $IncludeSourceVsSource = [bool]$cfg.IncludeSourceVsSource }
    }

    $SourceRunRoot = @($SourceRunRoot | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ([string]::IsNullOrWhiteSpace($TargetRunRoot)) { $TargetRunRoot = $null }

    if ($SourceRunRoot.Count -eq 0 -and -not $TargetRunRoot) {
        throw "Provide at least one SourceRunRoot or a TargetRunRoot (or a ConfigFile)."
    }

    foreach ($p in $SourceRunRoot) {
        if (-not (Test-Path -LiteralPath $p)) { throw "Source run root not found: $p" }
    }
    if ($TargetRunRoot -and -not (Test-Path -LiteralPath $TargetRunRoot)) {
        throw "Target run root not found: $TargetRunRoot"
    }

    # ---------------------------
    # Workspace layout
    # ---------------------------
    if (-not $WorkspaceRoot) {
        $ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $WorkspaceRoot = Join-Path (Get-Location).Path "AnalysisWorkspace_$ts"
    }

    $inputsDir = Join-Path $WorkspaceRoot '00_inputs'
    $analysisDir = Join-Path $WorkspaceRoot '30_analysis'
    $perRunDir = Join-Path $analysisDir 'per_run'
    $crossRunDir = Join-Path $analysisDir 'cross_run'
    $manifestDir = Join-Path $WorkspaceRoot '99_manifest'

    if (-not $WhatIf) {
        foreach ($d in @($WorkspaceRoot, $inputsDir, $analysisDir, $perRunDir, $crossRunDir, $manifestDir)) {
            if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        }
    }

    # ---------------------------
    # Helper functions (private)
    # ---------------------------
    function Get-DiscoveryIndexPath([string]$RunRoot) {
        foreach ($relativePath in @(
                '99_manifest\Discovery.Index.json',
                '99_manifest\Discovery__Index__Run.json'
            )) {
            $p = Join-Path $RunRoot $relativePath
            if (Test-Path -LiteralPath $p) { return $p }
        }
        return $null
    }

    function Load-DiscoveryIndex([string]$RunRoot) {
        $idxPath = Get-DiscoveryIndexPath $RunRoot
        if ($idxPath) {
            try {
                return Get-Content -LiteralPath $idxPath -Raw | ConvertFrom-Json
            } catch {
                throw "Failed to parse discovery index JSON: $idxPath :: $($_.Exception.Message)"
            }
        }

        # Fallback if index missing: minimal synthetic index by scanning CSV/JSON
        $files = Get-ChildItem -LiteralPath $RunRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.csv', '.json' } |
        Where-Object { $_.FullName -notmatch '[\\/](30_analysis|40_assessment)[\\/]' }

        $datasets = foreach ($f in $files) {
            $rel = $f.FullName.Substring($RunRoot.Length).TrimStart('\', '/')
            $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
            [pscustomobject]@{
                name             = "File.$([IO.Path]::GetFileNameWithoutExtension($f.Name))"
                kind             = 'Run'
                domainFqdn       = $null
                contentType      = if ($f.Extension -eq '.csv') { 'text/csv' } else { 'application/json' }
                path             = $rel
                sha256           = $hash
                bytes            = $f.Length
                rows             = $null
                lastWriteTimeUtc = $f.LastWriteTimeUtc.ToString('o')
                tags             = @()
            }
        }

        return [pscustomobject]@{
            schemaVersion  = '1.0'
            contract       = 'Discovery.v0_fallback'
            tool           = 'Unknown'
            toolVersion    = 'Unknown'
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            environment    = 'Unknown'
            customerName   = $null
            runRoot        = $RunRoot
            datasets       = $datasets
        }
    }

    function Get-RunIdFromIndex([string]$IndexPath) {
        $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $IndexPath).Hash.ToLowerInvariant()
        return $h.Substring(0, 12)
    }

    function Resolve-DatasetPaths {
        param(
            [Parameter(Mandatory)]$Index,
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][string]$DatasetName
        )

        $hits = @()
        if ($Index.PSObject.Properties['datasets']) {
            $hits = @($Index.datasets | Where-Object { $_.name -eq $DatasetName })
        }
        foreach ($d in $hits) {
            $full = Join-Path $RunRoot $d.path
            if (Test-Path -LiteralPath $full) {
                [pscustomobject]@{
                    name       = $d.name
                    kind       = $d.kind
                    domainFqdn = $d.domainFqdn
                    path       = $full
                    relPath    = $d.path
                    sha256     = $d.sha256
                }
            }
        }
    }

    function Import-CsvSafe([string]$Path) {
        if (-not (Test-Path -LiteralPath $Path)) { return @() }
        try { return @(Import-Csv -LiteralPath $Path -ErrorAction Stop) } catch { return @() }
    }

    function Get-PropertyValue {
        param($Obj, [string]$Name)
        if (-not $Obj) { return $null }
        $p = $Obj.PSObject.Properties[$Name]
        if ($p) { return $p.Value }
        return $null
    }

    function Normalize-Token([string]$s) {
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        return ($s.Trim().ToLowerInvariant())
    }

    function Split-MultiValue([object]$v) {
        if ($null -eq $v) { return @() }
        $s = [string]$v
        if ([string]::IsNullOrWhiteSpace($s)) { return @() }
        # common separators in exports: ';', ',', '|'
        $parts = $s -split '[;,\|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return @($parts)
    }

    function Get-ObjectId([psobject]$o) {
        foreach ($k in @('ObjectGuid', 'objectGuid', 'Guid', 'GUID', 'Id', 'ID')) {
            $v = Get-PropertyValue $o $k
            if ($v) { return [string]$v }
        }
        $dn = Get-PropertyValue $o 'DistinguishedName'
        if ($dn) { return [string]$dn }
        return [string]($o | ConvertTo-Json -Compress)
    }

    # ---------------------------
    # Register runs in workspace
    # ---------------------------
    $runs = @()

    foreach ($src in $SourceRunRoot) {
        $idxPath = Get-DiscoveryIndexPath $src
        if (-not $idxPath) { throw "Missing discovery index under: $src\99_manifest (expected Discovery.Index.json or Discovery__Index__Run.json)" }
        $idx = Load-DiscoveryIndex $src
        $runId = Get-RunIdFromIndex $idxPath

        $runs += [pscustomobject]@{
            runId                = $runId
            role                 = 'Source'
            runRoot              = $src
            discoveryIndexPath   = $idxPath
            discoveryIndexSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $idxPath).Hash.ToLowerInvariant()
            environment          = $idx.environment
            tool                 = $idx.tool
            toolVersion          = $idx.toolVersion
            analysisRoot         = (Join-Path $perRunDir $runId)
        }
    }

    if ($TargetRunRoot) {
        $idxPath = Get-DiscoveryIndexPath $TargetRunRoot
        if (-not $idxPath) { throw "Missing discovery index under: $TargetRunRoot\99_manifest (expected Discovery.Index.json or Discovery__Index__Run.json)" }
        $idx = Load-DiscoveryIndex $TargetRunRoot
        $runId = Get-RunIdFromIndex $idxPath

        $runs += [pscustomobject]@{
            runId                = $runId
            role                 = 'Target'
            runRoot              = $TargetRunRoot
            discoveryIndexPath   = $idxPath
            discoveryIndexSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $idxPath).Hash.ToLowerInvariant()
            environment          = $idx.environment
            tool                 = $idx.tool
            toolVersion          = $idx.toolVersion
            analysisRoot         = (Join-Path $perRunDir $runId)
        }
    }

    # Create per-run analysis folders (placeholder for future run-level steps)
    if (-not $WhatIf) {
        foreach ($r in $runs) {
            if (-not (Test-Path -LiteralPath $r.analysisRoot)) { New-Item -ItemType Directory -Path $r.analysisRoot -Force | Out-Null }
        }
    }

    # Persist runs registry
    $runsPath = Join-Path $manifestDir 'Workspace__Runs__Workspace.json'
    if (-not $WhatIf) {
        [pscustomobject]@{
            schemaVersion  = '1.0'
            contract       = 'Analysis.WorkspaceRuns.v1'
            generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            workspaceRoot  = $WorkspaceRoot
            runs           = $runs
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runsPath -Encoding UTF8
    }

    # ---------------------------
    # Cross-run dataset 1: Identity collisions
    # ---------------------------
    function New-CrossRunIdentityCollisions {
        param(
            [Parameter(Mandatory)][psobject[]]$Runs,
            [Parameter(Mandatory)][string]$OutCsvPath
        )

        $collisions = New-Object System.Collections.Generic.List[object]

        # Build map: CollisionType|NormalizedValue -> list of occurrences
        $map = @{}

        function Add-Occurrence {
            param(
                [string]$CollisionType,
                [string]$Value,
                [pscustomobject]$Occurrence
            )
            $nv = Normalize-Token $Value
            if (-not $nv) { return }

            $key = "$CollisionType|$nv"
            if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.Generic.List[object] }
            $map[$key].Add($Occurrence)
        }

        foreach ($r in $Runs) {
            $idx = Load-DiscoveryIndex $r.runRoot

            # Users
            foreach ($ds in @(Resolve-DatasetPaths -Index $idx -RunRoot $r.runRoot -DatasetName 'Domain.Users')) {
                $rows = Import-CsvSafe $ds.path
                foreach ($o in $rows) {
                    $occBase = [pscustomobject]@{
                        RunId             = $r.runId
                        Role              = $r.role
                        Environment       = $r.environment
                        DomainFqdn        = $ds.domainFqdn
                        ObjectType        = 'User'
                        ObjectId          = Get-ObjectId $o
                        SamAccountName    = Get-PropertyValue $o 'SamAccountName'
                        UserPrincipalName = Get-PropertyValue $o 'UserPrincipalName'
                        Mail              = Get-PropertyValue $o 'Mail'
                    }

                    if ($CollisionKeysUser -contains 'SamAccountName') { Add-Occurrence 'User.SamAccountName'    $occBase.SamAccountName $occBase }
                    if ($CollisionKeysUser -contains 'UserPrincipalName') { Add-Occurrence 'User.UPN'               $occBase.UserPrincipalName $occBase }
                    if ($CollisionKeysUser -contains 'Mail') { Add-Occurrence 'User.Mail'              $occBase.Mail $occBase }

                    if ($CollisionKeysUser -contains 'ProxyAddresses') {
                        foreach ($p in (Split-MultiValue (Get-PropertyValue $o 'ProxyAddresses'))) {
                            Add-Occurrence 'User.ProxyAddress' $p $occBase
                        }
                    }
                    if ($CollisionKeysUser -contains 'ServicePrincipalName') {
                        foreach ($s in (Split-MultiValue (Get-PropertyValue $o 'ServicePrincipalName'))) {
                            Add-Occurrence 'User.SPN' $s $occBase
                        }
                    }
                }
            }

            # Groups
            foreach ($ds in @(Resolve-DatasetPaths -Index $idx -RunRoot $r.runRoot -DatasetName 'Domain.Groups')) {
                $rows = Import-CsvSafe $ds.path
                foreach ($o in $rows) {
                    $occBase = [pscustomobject]@{
                        RunId          = $r.runId
                        Role           = $r.role
                        Environment    = $r.environment
                        DomainFqdn     = $ds.domainFqdn
                        ObjectType     = 'Group'
                        ObjectId       = Get-ObjectId $o
                        SamAccountName = Get-PropertyValue $o 'SamAccountName'
                        Mail           = Get-PropertyValue $o 'Mail'
                    }

                    if ($CollisionKeysGroup -contains 'SamAccountName') { Add-Occurrence 'Group.SamAccountName' $occBase.SamAccountName $occBase }
                    if ($CollisionKeysGroup -contains 'Mail') { Add-Occurrence 'Group.Mail'          $occBase.Mail $occBase }
                    if ($CollisionKeysGroup -contains 'ProxyAddresses') {
                        foreach ($p in (Split-MultiValue (Get-PropertyValue $o 'ProxyAddresses'))) {
                            Add-Occurrence 'Group.ProxyAddress' $p $occBase
                        }
                    }
                }
            }

            # Computers
            foreach ($ds in @(Resolve-DatasetPaths -Index $idx -RunRoot $r.runRoot -DatasetName 'Domain.Computers.All')) {
                $rows = Import-CsvSafe $ds.path
                foreach ($o in $rows) {
                    $occBase = [pscustomobject]@{
                        RunId       = $r.runId
                        Role        = $r.role
                        Environment = $r.environment
                        DomainFqdn  = $ds.domainFqdn
                        ObjectType  = 'Computer'
                        ObjectId    = Get-ObjectId $o
                        Name        = Get-PropertyValue $o 'Name'
                        DnsHostName = Get-PropertyValue $o 'DnsHostName'
                    }

                    if ($CollisionKeysComputer -contains 'Name') { Add-Occurrence 'Computer.Name'       $occBase.Name $occBase }
                    if ($CollisionKeysComputer -contains 'DnsHostName') { Add-Occurrence 'Computer.DnsHostName' $occBase.DnsHostName $occBase }

                    if ($CollisionKeysComputer -contains 'ServicePrincipalName') {
                        foreach ($s in (Split-MultiValue (Get-PropertyValue $o 'ServicePrincipalName'))) {
                            Add-Occurrence 'Computer.SPN' $s $occBase
                        }
                    }
                }
            }
        }

        # Emit collisions
        foreach ($k in $map.Keys) {
            $parts = $k.Split('|', 2)
            $ctype = $parts[0]
            $val = $parts[1]
            $list = @()
            foreach ($occurrence in $map[$k]) {
                $list += $occurrence
            }

            # Only a "collision" if:
            # - multiple objects, AND
            # - spans >1 run OR >1 role
            if ($list.Count -lt 2) { continue }

            $runIds = @($list | Select-Object -ExpandProperty RunId -Unique)
            $roles = @($list | Select-Object -ExpandProperty Role -Unique)

            if ($runIds.Count -lt 2 -and $roles.Count -lt 2) { continue }

            # compact object summary for human scan
            $objSummary = $list | ForEach-Object {
                "{0}:{1}:{2}:{3}" -f $_.Role, $_.ObjectType, $_.DomainFqdn, $_.ObjectId
            }

            $collisions.Add([pscustomobject]@{
                    CollisionType   = $ctype
                    Value           = $val
                    OccurrenceCount = $list.Count
                    RunsInvolved    = ($runIds -join ';')
                    RolesInvolved   = ($roles -join ';')
                    Objects         = ($objSummary -join ' | ')
                })
        }

        $collisions = @($collisions | Sort-Object CollisionType, Value)

        if ($collisions.Count -gt 0) {
            $collisions | Export-Csv -LiteralPath $OutCsvPath -NoTypeInformation -Force
        } else {
            # Write empty file with headers for pipeline stability
            "" | Out-File -LiteralPath $OutCsvPath -Encoding UTF8
            "CollisionType,Value,OccurrenceCount,RunsInvolved,RolesInvolved,Objects" | Out-File -LiteralPath $OutCsvPath -Append -Encoding UTF8
        }

        return $collisions.Count
    }

    $identityCollisionsPath = Join-Path $crossRunDir 'AD__CrossRun__IdentityCollisions.csv'

    # If only one run and user didn't ask for source-vs-source, collisions are usually meaningless.
    $shouldRunCollisions = $false
    if ($runs.Count -ge 2) { $shouldRunCollisions = $true }

    if (-not $WhatIf -and $shouldRunCollisions) {
        Write-Host "Generating cross-run identity collisions..." -ForegroundColor Cyan
        $cnt = New-CrossRunIdentityCollisions -Runs $runs -OutCsvPath $identityCollisionsPath
        Write-Host "  Wrote: $identityCollisionsPath ($cnt collisions)" -ForegroundColor Green
    }

    # ---------------------------
    # Cross-run dataset 2: Password policy diff
    # ---------------------------
    function Convert-RowToComparableHashtable {
        param([psobject]$Row)

        $h = @{}
        foreach ($p in $Row.PSObject.Properties) {
            # drop noisy fields if present
            if ($p.Name -in @('PSComputerName', 'RunId', 'Role', 'Environment', 'DomainFqdn')) { continue }
            $val = $p.Value
            if ($null -eq $val) { $val = '' }
            $h[$p.Name] = [string]$val
        }
        return $h
    }

    function New-CrossRunPasswordPolicyDiff {
        param(
            [Parameter(Mandatory)][psobject[]]$Runs,
            [Parameter(Mandatory)][string]$OutCsvPath,
            [switch]$IncludeSourceVsSource
        )

        $sources = @($Runs | Where-Object Role -eq 'Source')
        $targets = @($Runs | Where-Object Role -eq 'Target')

        $diffs = New-Object System.Collections.Generic.List[object]

        function Load-PoliciesForRun {
            param([pscustomobject]$Run)

            $idx = Load-DiscoveryIndex $Run.runRoot

            $pol = New-Object System.Collections.Generic.List[object]

            # Default policy (usually 1 row per domain)
            foreach ($ds in @(Resolve-DatasetPaths -Index $idx -RunRoot $Run.runRoot -DatasetName 'Domain.PasswordPolicy.Default')) {
                foreach ($r in (Import-CsvSafe $ds.path)) {
                    $pol.Add([pscustomobject]@{
                            RunId       = $Run.runId
                            Role        = $Run.role
                            Environment = $Run.environment
                            DomainFqdn  = (Get-PropertyValue $r 'DomainFqdn')
                            PolicyType  = 'Default'
                            PolicyName  = (Get-PropertyValue $r 'DomainFqdn')
                            Row         = $r
                        })
                }
            }

            # FGPP (0..n rows per domain)
            foreach ($ds in @(Resolve-DatasetPaths -Index $idx -RunRoot $Run.runRoot -DatasetName 'Domain.PasswordPolicy.FGPP')) {
                foreach ($r in (Import-CsvSafe $ds.path)) {
                    $name = (Get-PropertyValue $r 'Name')
                    if (-not $name) { $name = '(UnnamedFGPP)' }
                    $pol.Add([pscustomobject]@{
                            RunId       = $Run.runId
                            Role        = $Run.role
                            Environment = $Run.environment
                            DomainFqdn  = (Get-PropertyValue $r 'DomainFqdn')
                            PolicyType  = 'FGPP'
                            PolicyName  = $name
                            Row         = $r
                        })
                }
            }

            $policies = @()
            foreach ($policy in $pol) {
                $policies += $policy
            }

            return $policies
        }

        # Build per-run policy sets
        $runPolicies = @{}
        foreach ($r in $Runs) {
            $runPolicies[$r.runId] = Load-PoliciesForRun $r
        }

        function Diff-PolicyPair {
            param(
                [pscustomobject]$LeftRun,
                [pscustomobject]$RightRun
            )

            $left = @()
            foreach ($policy in $runPolicies[$LeftRun.runId]) {
                $left += $policy
            }

            $right = @()
            foreach ($policy in $runPolicies[$RightRun.runId]) {
                $right += $policy
            }

            # Index by (DomainFqdn|Type|Name)
            $lMap = @{}
            foreach ($p in $left) { $lMap["$($p.DomainFqdn)|$($p.PolicyType)|$($p.PolicyName)"] = $p }
            $rMap = @{}
            foreach ($p in $right) { $rMap["$($p.DomainFqdn)|$($p.PolicyType)|$($p.PolicyName)"] = $p }

            $keys = @((@($lMap.Keys) + @($rMap.Keys)) | Sort-Object -Unique)

            foreach ($k in $keys) {
                $lp = $lMap[$k]
                $rp = $rMap[$k]

                if (-not $lp -and -not $rp) { continue }

                $domain = ($k -split '\|')[0]
                $ptype = ($k -split '\|')[1]
                $pname = ($k -split '\|')[2]

                if (-not $lp) {
                    $diffs.Add([pscustomobject]@{
                            DomainFqdn  = $domain
                            PolicyType  = $ptype
                            PolicyName  = $pname
                            LeftRole    = $LeftRun.role
                            LeftRunId   = $LeftRun.runId
                            RightRole   = $RightRun.role
                            RightRunId  = $RightRun.runId
                            Property    = '(PolicyMissing)'
                            LeftValue   = ''
                            RightValue  = 'Present'
                            IsDifferent = $true
                        })
                    continue
                }

                if (-not $rp) {
                    $diffs.Add([pscustomobject]@{
                            DomainFqdn  = $domain
                            PolicyType  = $ptype
                            PolicyName  = $pname
                            LeftRole    = $LeftRun.role
                            LeftRunId   = $LeftRun.runId
                            RightRole   = $RightRun.role
                            RightRunId  = $RightRun.runId
                            Property    = '(PolicyMissing)'
                            LeftValue   = 'Present'
                            RightValue  = ''
                            IsDifferent = $true
                        })
                    continue
                }

                $lh = Convert-RowToComparableHashtable $lp.Row
                $rh = Convert-RowToComparableHashtable $rp.Row

                $props = @($lh.Keys + $rh.Keys | Sort-Object -Unique)
                foreach ($prop in $props) {
                    if ($prop -in @('DomainFqdn', 'Name')) { continue }
                    $lv = if ($lh.ContainsKey($prop)) { $lh[$prop] } else { '' }
                    $rv = if ($rh.ContainsKey($prop)) { $rh[$prop] } else { '' }

                    if ($lv -ne $rv) {
                        $diffs.Add([pscustomobject]@{
                                DomainFqdn  = $domain
                                PolicyType  = $ptype
                                PolicyName  = $pname
                                LeftRole    = $LeftRun.role
                                LeftRunId   = $LeftRun.runId
                                RightRole   = $RightRun.role
                                RightRunId  = $RightRun.runId
                                Property    = $prop
                                LeftValue   = $lv
                                RightValue  = $rv
                                IsDifferent = $true
                            })
                    }
                }
            }
        }

        if ($targets.Count -gt 0 -and $sources.Count -gt 0) {
            # Compare each source against the (single) target
            $t = $targets[0]
            foreach ($s in $sources) {
                Diff-PolicyPair -LeftRun $s -RightRun $t
            }
        } elseif ($IncludeSourceVsSource -and $sources.Count -gt 1) {
            # Pairwise source comparisons (can grow quickly; opt-in)
            for ($i = 0; $i -lt $sources.Count; $i++) {
                for ($j = $i + 1; $j -lt $sources.Count; $j++) {
                    Diff-PolicyPair -LeftRun $sources[$i] -RightRun $sources[$j]
                }
            }
        } else {
            # no valid cross-run comparison scenario
        }

        $out = @($diffs | Sort-Object DomainFqdn, PolicyType, PolicyName, Property)

        if ($out.Count -gt 0) {
            $out | Export-Csv -LiteralPath $OutCsvPath -NoTypeInformation -Force
        } else {
            "" | Out-File -LiteralPath $OutCsvPath -Encoding UTF8
            "DomainFqdn,PolicyType,PolicyName,LeftRole,LeftRunId,RightRole,RightRunId,Property,LeftValue,RightValue,IsDifferent" | Out-File -LiteralPath $OutCsvPath -Append -Encoding UTF8
        }

        return $out.Count
    }

    $pwdDiffPath = Join-Path $crossRunDir 'AD__CrossRun__PasswordPolicyDiff.csv'

    $shouldRunPwdDiff = $false
    if ($runs.Count -ge 2) { $shouldRunPwdDiff = $true }

    if (-not $WhatIf -and $shouldRunPwdDiff) {
        Write-Host "Generating cross-run password policy diff..." -ForegroundColor Cyan
        $cnt = New-CrossRunPasswordPolicyDiff -Runs $runs -OutCsvPath $pwdDiffPath -IncludeSourceVsSource:$IncludeSourceVsSource
        Write-Host "  Wrote: $pwdDiffPath ($cnt diffs)" -ForegroundColor Green
    }

    # ---------------------------
    # Workspace index (summary)
    # ---------------------------
    $workspaceIndexPath = Join-Path $manifestDir 'Workspace__Index__Workspace.json'
    if (-not $WhatIf) {
        $produced = @()
        if (Test-Path -LiteralPath $identityCollisionsPath) { $produced += @{ name = 'CrossRun.IdentityCollisions'; path = (Split-Path -Leaf $identityCollisionsPath) } }
        if (Test-Path -LiteralPath $pwdDiffPath) { $produced += @{ name = 'CrossRun.PasswordPolicyDiff'; path = (Split-Path -Leaf $pwdDiffPath) } }

        [pscustomobject]@{
            schemaVersion    = '1.0'
            contract         = 'Analysis.Workspace.v1'
            generatedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
            workspaceRoot    = $WorkspaceRoot
            inputs           = [pscustomobject]@{
                sourceRunCount = @($runs | Where-Object Role -eq 'Source').Count
                hasTarget      = [bool](@($runs | Where-Object Role -eq 'Target').Count -gt 0)
            }
            runsManifestPath = '99_manifest/Workspace__Runs__Workspace.json'
            outputs          = [pscustomobject]@{
                crossRun = @(
                    [pscustomobject]@{ name = 'CrossRun.IdentityCollisions'; path = '30_analysis/cross_run/AD__CrossRun__IdentityCollisions.csv' },
                    [pscustomobject]@{ name = 'CrossRun.PasswordPolicyDiff'; path = '30_analysis/cross_run/AD__CrossRun__PasswordPolicyDiff.csv' }
                )
            }
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $workspaceIndexPath -Encoding UTF8
    }

    return [pscustomobject]@{
        WorkspaceRoot         = $WorkspaceRoot
        RunsManifest          = $runsPath
        WorkspaceIndex        = $workspaceIndexPath
        IdentityCollisionsCsv = $identityCollisionsPath
        PasswordPolicyDiffCsv = $pwdDiffPath
        RunCount              = $runs.Count
    }
}
