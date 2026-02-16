<#
.SYNOPSIS
  Analyzes SharpHound/BloodHound JSON output and produces AD security findings.

.DESCRIPTION
  - Consumes normalized SharpHound JSON files produced by Invoke-SATSharpHoundCollection.ps1
  - Produces findings, evidence CSVs, and metadata
  - Profile-aware (LowImpact / Standard / Deep)
  - Designed to be safe and defensible in client environments
#>

function Invoke-SATBloodHoundAnalysis {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$InputPath,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$OutputRoot,

        [string]$ConfigRoot,

        [string]$SnapshotTimestamp
    )

    Set-StrictMode -Version Latest

    if (-not (Test-Path $InputPath)) {
        throw "InputPath not found: $InputPath"
    }

    $assessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    $logsDir = Join-Path $assessmentPath 'Logs'
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }

    $logPath = Join-Path $logsDir 'RunLog.txt'
    Write-SATLog -Message "Invoke-SATBloodHoundAnalysis started. Profile=$Profile" -LogPath $logPath

    $evidenceRoot = Join-Path $assessmentPath 'Evidence'
    $bhDir = Join-Path $evidenceRoot 'BloodHound'
    if (-not (Test-Path $bhDir)) {
        New-Item -Path $bhDir -ItemType Directory -Force | Out-Null
    }

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $ConfigRoot) {
        $ConfigRoot = Join-Path $moduleRoot 'config'
    }

    $severityMapPath = Join-Path $ConfigRoot 'severity_map.json'
    $thresholdsPath = Join-Path $ConfigRoot 'thresholds.json'

    $severityMap = @{
        Informational = 0
        Low           = 1
        Medium        = 2
        High          = 3
        Critical      = 4
    }

    if (Test-Path $severityMapPath) {
        $map = Get-Content -Path $severityMapPath -Raw | ConvertFrom-Json
        foreach ($key in $map.PSObject.Properties.Name) {
            $severityMap[$key] = [int]$map.$key
        }
    }

    $thresholds = [pscustomobject]@{}
    if (Test-Path $thresholdsPath) {
        $thresholds = Get-Content -Path $thresholdsPath -Raw | ConvertFrom-Json
    }

    function Get-ThresholdSet {
        param (
            [string]$Name,
            [hashtable]$Fallback
        )

        $set = $thresholds.$Name
        if (-not $set) {
            return $Fallback
        }

        return @{
            Low    = [int]$set.Low
            Medium = [int]$set.Medium
            High   = [int]$set.High
        }
    }

    function Get-SeverityFromCount {
        param (
            [int]$Count,
            [hashtable]$ThresholdSet
        )

        if ($Count -ge $ThresholdSet.High) { return 'High' }
        if ($Count -ge $ThresholdSet.Medium) { return 'Medium' }
        if ($Count -ge $ThresholdSet.Low) { return 'Low' }
        return 'Informational'
    }

    # Robust time conversion: supports Unix seconds OR Windows FileTime
    function Convert-BhTime {
        param (
            [object]$Value
        )

        if ($null -eq $Value) { return $null }

        $num = 0
        if (-not [double]::TryParse($Value.ToString(), [ref]$num)) { return $null }
        if ($num -le 0) { return $null }

        try {
            # FileTime values are much larger (100ns ticks since 1601)
            if ($num -ge 100000000000000) {
                return [DateTime]::FromFileTimeUtc([int64]$num)
            }

            return [DateTimeOffset]::FromUnixTimeSeconds([int64]$num).UtcDateTime
        } catch {
            return $null
        }
    }

    function Get-DaysSince {
        param (
            [object]$TimestampValue
        )

        $dt = Convert-BhTime -Value $TimestampValue
        if (-not $dt) { return $null }
        return [int]([DateTime]::UtcNow - $dt).TotalDays
    }

    function New-Finding {
        param (
            [string]$FindingId,
            [string]$Category,
            [string]$Title,
            [string]$Severity,
            [string]$Asset,
            [string]$Domain,
            [int]$EvidenceCount,
            [string]$EvidenceSource,
            [string]$EvidenceRef,
            [string]$Recommendation,
            [string]$PolicyRef,
            [string]$Profile,
            [string]$Tool
        )

        $riskScore = 0
        if ($Severity -and $severityMap.ContainsKey($Severity)) {
            $baseScore = [int]$severityMap[$Severity]
            $bonus = if ($EvidenceCount -ge 50) { 1 } else { 0 }
            $riskScore = [Math]::Min(4, ($baseScore + $bonus))
        }

        [pscustomobject]@{
            FindingId      = $FindingId
            Category       = $Category
            Title          = $Title
            Severity       = $Severity
            RiskScore      = $riskScore
            Asset          = $Asset
            Domain         = $Domain
            EvidenceCount  = $EvidenceCount
            EvidenceSource = $EvidenceSource
            EvidenceRef    = $EvidenceRef
            Recommendation = $Recommendation
            PolicyRef      = $PolicyRef
            Profile        = $Profile
            Tool           = $Tool
            Timestamp      = (Get-Date -Format 's')
        }
    }

    function Add-EvidenceIndex {
        param (
            [System.Collections.Generic.List[object]]$Index,
            [string]$FindingId,
            [string]$EvidencePath,
            [string]$Domain,
            [string]$Notes
        )

        $fileName = Split-Path $EvidencePath -Leaf
        $ext = [System.IO.Path]::GetExtension($fileName).TrimStart('.').ToLowerInvariant()
        $type = if ($ext) { $ext } else { 'unknown' }

        $Index.Add([pscustomobject]@{
                FindingId    = $FindingId
                EvidenceFile = $fileName
                EvidenceType = $type
                Domain       = $Domain
                Notes        = $Notes
            })
    }

    function Get-AcePrincipal {
        param([object]$Ace)

        if ($null -eq $Ace) { return $null }

        if ($Ace.PSObject.Properties['PrincipalName'] -and $Ace.PrincipalName) { return [string]$Ace.PrincipalName }
        if ($Ace.PSObject.Properties['PrincipalSID'] -and $Ace.PrincipalSID) { return [string]$Ace.PrincipalSID }
        return $null
    }

    # Locate timestamped snapshot files
    $files = Get-ChildItem -Path $InputPath -Filter '*.json' -File
    $candidates = @()
    foreach ($file in $files) {
        if ($file.Name -match '^(?<ts>\d{14})_(?<type>.+)\.json$') {
            $candidates += [pscustomobject]@{
                Timestamp = $matches.ts
                Type      = $matches.type
                Path      = $file.FullName
            }
        }
    }

    if ($candidates.Count -eq 0) {
        throw "No BloodHound JSON files found in $InputPath"
    }

    if (-not $SnapshotTimestamp) {
        $SnapshotTimestamp = ($candidates | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
    }

    $snapshotFiles = @($candidates | Where-Object { $_.Timestamp -eq $SnapshotTimestamp })
    if ($snapshotFiles.Count -eq 0) {
        throw "No BloodHound JSON files found for timestamp $SnapshotTimestamp"
    }

    function Read-BhData {
        param (
            [string]$TypeName
        )

        $file = $snapshotFiles | Where-Object { $_.Type -eq $TypeName } | Select-Object -First 1
        if (-not $file) { return @() }

        $json = Get-Content -Path $file.Path -Raw | ConvertFrom-Json
        if ($json.PSObject.Properties['data']) {
            return @($json.data)
        }

        # Defensive fallback: if it's a bare array (rare)
        if ($json -is [System.Collections.IEnumerable] -and -not ($json -is [string])) {
            return @($json)
        }

        return @()
    }

    # Load datasets we need for the new findings
    $usersRaw = Read-BhData -TypeName 'users'
    $computersRaw = Read-BhData -TypeName 'computers'
    $groupsRaw = Read-BhData -TypeName 'groups'
    $domainsRaw = Read-BhData -TypeName 'domains'
    $ousRaw = Read-BhData -TypeName 'ous'
    $containersRaw = Read-BhData -TypeName 'containers'

    # Map to friendly objects (keep Aces)
    $users = foreach ($row in $usersRaw) {
        $p = $row.Properties
        [pscustomobject]@{
            DomainFqdn              = [string]$p.domain
            Name                    = [string]$p.name
            SamAccountName          = [string]$p.samaccountname
            Enabled                 = [bool]$p.enabled
            HasSpn                  = [bool]$p.hasspn
            SpnCount                = @($p.serviceprincipalnames).Count
            UnconstrainedDelegation = [bool]$p.unconstraineddelegation
            PasswordNeverExpires    = [bool]$p.pwdneverexpires
            DontRequirePreauth      = [bool]$p.dontreqpreauth
            PasswordNotRequired     = [bool]$p.passwordnotreqd
            AdminCount              = [bool]$p.admincount
            LastLogonTimestamp      = $p.lastlogontimestamp
            PasswordLastSet         = $p.pwdlastset
            DistinguishedName       = [string]$p.distinguishedname
            Aces                    = $row.Aces
        }
    }

    $computers = foreach ($row in $computersRaw) {
        $p = $row.Properties
        $rbcdVal = $null
        foreach ($k in @('msds-allowedtoactonbehalfofotheridentity', 'msDS-AllowedToActOnBehalfOfOtherIdentity', 'allowedtoactonbehalfofotheridentity')) {
            if ($p.PSObject.Properties[$k]) { $rbcdVal = $p.$k; break }
        }

        [pscustomobject]@{
            DomainFqdn              = [string]$p.domain
            Name                    = [string]$p.name
            SamAccountName          = [string]$p.samaccountname
            Enabled                 = [bool]$p.enabled
            IsDc                    = [bool]$p.isdc
            HasLaps                 = [bool]$p.haslaps
            OperatingSystem         = [string]$p.operatingsystem
            UnconstrainedDelegation = [bool]$p.unconstraineddelegation
            SpnCount                = @($p.serviceprincipalnames).Count
            LastLogonTimestamp      = $p.lastlogontimestamp
            PasswordLastSet         = $p.pwdlastset
            DistinguishedName       = [string]$p.distinguishedname
            HasRBCD                 = [bool]($null -ne $rbcdVal -and $rbcdVal.ToString().Length -gt 0)
            Aces                    = $row.Aces
            PrivilegedSessions      = if ($row.PSObject.Properties['PrivilegedSessions']) { $row.PrivilegedSessions.Results } else { @() }
            LocalGroups             = if ($row.PSObject.Properties['LocalGroups']) { $row.LocalGroups } else { $null }
        }
    }

    $groups = foreach ($row in $groupsRaw) {
        $p = $row.Properties
        [pscustomobject]@{
            DomainFqdn        = [string]$p.domain
            Name              = [string]$p.name
            SamAccountName    = [string]$p.samaccountname
            DistinguishedName = [string]$p.distinguishedname
            Aces              = $row.Aces
        }
    }

    $domains = foreach ($row in $domainsRaw) {
        $p = $row.Properties
        [pscustomobject]@{
            DomainFqdn        = [string]$p.domain
            Name              = [string]$p.name
            DistinguishedName = [string]$p.distinguishedname
            Aces              = $row.Aces
        }
    }

    $ous = foreach ($row in $ousRaw) {
        $p = $row.Properties
        [pscustomobject]@{
            DomainFqdn        = [string]$p.domain
            Name              = [string]$p.name
            DistinguishedName = [string]$p.distinguishedname
            Aces              = $row.Aces
        }
    }

    $containers = foreach ($row in $containersRaw) {
        $p = $row.Properties
        [pscustomobject]@{
            DomainFqdn        = [string]$p.domain
            Name              = [string]$p.name
            DistinguishedName = [string]$p.distinguishedname
            Aces              = $row.Aces
        }
    }

    function Find-AdminSDHolderObjects {
        param(
            [object[]]$Containers,
            [object[]]$Ous,
            [object[]]$Domains
        )

        $hits = New-Object System.Collections.Generic.List[object]

        # Preferred: containers
        if ($Containers -and $Containers.Count -gt 0) {
            foreach ($c in $Containers) {
                if (($c.Name -match 'AdminSDHolder') -or ($c.DistinguishedName -and $c.DistinguishedName -match 'CN=AdminSDHolder')) {
                    $hits.Add($c)
                }
            }
            if ($hits.Count -gt 0) { return @($hits) }
        }

        # Fallback: scan OUs and domains by DN
        foreach ($o in @($Ous + $Domains)) {
            if ($null -eq $o) { continue }
            if ($o.DistinguishedName -and $o.DistinguishedName -match 'CN=AdminSDHolder') {
                $hits.Add($o)
            }
        }

        return @($hits)
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $evidenceIndex = New-Object System.Collections.Generic.List[object]

    # -----------------------------
    # Existing findings (unchanged behavior, but exports now UTF8)
    # -----------------------------
    $kerberoastable = @($users | Where-Object { $_.HasSpn -or $_.SpnCount -gt 0 })
    if ($kerberoastable.Count -gt 0) {
        $thresholdsKerb = Get-ThresholdSet -Name 'KerberoastableAccounts' -Fallback @{ Low = 1; Medium = 5; High = 20 }
        $severity = Get-SeverityFromCount -Count $kerberoastable.Count -ThresholdSet $thresholdsKerb

        $evidencePath = Join-Path $bhDir ("BH-SVC-001-kerberoastable-{0}.csv" -f $SnapshotTimestamp)
        $kerberoastable | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-SVC-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Users with SPNs (kerberoastable baseline)'

        $findings.Add((New-Finding -FindingId 'BH-SVC-001' `
                    -Category 'Identity' `
                    -Title 'Kerberoastable service accounts (SPNs present)' `
                    -Severity $severity `
                    -Asset 'Service Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $kerberoastable.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Review SPN accounts, rotate passwords, and enforce AES-only Kerberos where possible.' `
                    -PolicyRef 'CIS AD (Kerberos); Microsoft Kerberos hardening guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    $unconstrainedUsers = @($users | Where-Object { $_.UnconstrainedDelegation -eq $true })
    $unconstrainedComputers = @($computers | Where-Object { $_.UnconstrainedDelegation -eq $true })
    $unconstrainedAll = @($unconstrainedUsers + $unconstrainedComputers)
    if ($unconstrainedAll.Count -gt 0) {
        $severity = 'High'
        $evidencePath = Join-Path $bhDir ("BH-DELEG-001-unconstrained-{0}.csv" -f $SnapshotTimestamp)
        $unconstrainedAll | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-DELEG-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Unconstrained delegation enabled (users/computers)'

        $findings.Add((New-Finding -FindingId 'BH-DELEG-001' `
                    -Category 'Identity' `
                    -Title 'Unconstrained delegation enabled' `
                    -Severity $severity `
                    -Asset 'Delegation Settings' `
                    -Domain 'All' `
                    -EvidenceCount $unconstrainedAll.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Replace unconstrained delegation with constrained or resource-based delegation.' `
                    -PolicyRef 'CIS AD (delegation); Microsoft Kerberos delegation guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    $pneUsers = @($users | Where-Object { $_.PasswordNeverExpires -eq $true })
    if ($pneUsers.Count -gt 0) {
        $thresholdsPne = Get-ThresholdSet -Name 'PasswordNeverExpires' -Fallback @{ Low = 1; Medium = 5; High = 20 }
        $severity = Get-SeverityFromCount -Count $pneUsers.Count -ThresholdSet $thresholdsPne

        $evidencePath = Join-Path $bhDir ("BH-ACCT-001-password-never-expires-{0}.csv" -f $SnapshotTimestamp)
        $pneUsers | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-ACCT-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Users with PasswordNeverExpires'

        $findings.Add((New-Finding -FindingId 'BH-ACCT-001' `
                    -Category 'Identity' `
                    -Title 'Accounts with PasswordNeverExpires enabled' `
                    -Severity $severity `
                    -Asset 'User Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $pneUsers.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Disable PasswordNeverExpires for user accounts; use managed service accounts for exceptions.' `
                    -PolicyRef 'CIS AD (password policy); Microsoft identity guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    $adminCountUsers = @($users | Where-Object { $_.AdminCount -eq $true })
    if ($adminCountUsers.Count -gt 0) {
        $thresholdsAdmin = Get-ThresholdSet -Name 'AdminCountUsers' -Fallback @{ Low = 1; Medium = 5; High = 20 }
        $severity = Get-SeverityFromCount -Count $adminCountUsers.Count -ThresholdSet $thresholdsAdmin

        $evidencePath = Join-Path $bhDir ("BH-PRIV-001-admincount-{0}.csv" -f $SnapshotTimestamp)
        $adminCountUsers | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-PRIV-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Users with AdminCount=1'

        $findings.Add((New-Finding -FindingId 'BH-PRIV-001' `
                    -Category 'Identity' `
                    -Title 'Protected accounts (AdminCount=1)' `
                    -Severity $severity `
                    -Asset 'Privileged Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $adminCountUsers.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Review AdminCount=1 accounts; validate current privileged group membership and clean up orphaned entries.' `
                    -PolicyRef 'CIS AD (privileged access); Microsoft Tier 0 guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    # -----------------------------
    # NEW FINDINGS 1–5 + AdminSDHolder Tier0 (BH-TIER0-001)
    # -----------------------------

    $dangerRightsTier0 = @('GenericAll', 'WriteDacl', 'WriteOwner', 'GenericWrite', 'AllExtendedRights', 'AddMember', 'WriteMembers', 'ForceChangePassword', 'AddKeyCredentialLink')
    $excludePrincipalPatternsTier0 = @(
        'DOMAIN ADMINS',
        'ENTERPRISE ADMINS',
        'ADMINISTRATORS',
        'NT AUTHORITY\\SYSTEM',
        'BUILTIN\\ADMINISTRATORS'
    )

    function Is-ExcludedPrincipal {
        param([string]$Principal)

        if (-not $Principal) { return $true } # nothing to evaluate
        $p = $Principal.ToUpper()
        foreach ($ex in $excludePrincipalPatternsTier0) {
            if ($p -like "*$($ex.ToUpper())*") { return $true }
        }
        return $false
    }

    # 1) BH-DC-001 DCSync principals (domain replication rights)
    $dcsyncRights = @('GetChanges', 'GetChangesAll', 'GetChangesInFilteredSet', 'Replicating Directory Changes', 'Replicating Directory Changes All', 'Replicating Directory Changes In Filtered Set')
    $dcsyncRows = @()
    foreach ($d in $domains) {
        if (-not $d.Aces) { continue }
        foreach ($ace in $d.Aces) {
            if ($ace.IsInherited -eq $true) { continue }
            if (-not ($dcsyncRights -contains $ace.RightName)) { continue }

            $principal = Get-AcePrincipal -Ace $ace
            if (-not $principal) { continue }
            if (Is-ExcludedPrincipal -Principal $principal) { continue }

            $dcsyncRows += [pscustomobject]@{
                Domain        = $d.DomainFqdn
                DomainObject  = $d.Name
                RightName     = $ace.RightName
                Principal     = $principal
                PrincipalType = $ace.PrincipalType
            }
        }
    }

    if ($dcsyncRows.Count -gt 0) {
        $evidencePath = Join-Path $bhDir ("BH-DC-001-dcsync-principals-{0}.csv" -f $SnapshotTimestamp)
        $dcsyncRows | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-DC-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Non-standard principals with directory replication (DCSync) rights'

        $findings.Add((New-Finding -FindingId 'BH-DC-001' `
                    -Category 'Identity' `
                    -Title 'DCSync-capable principals detected (directory replication rights)' `
                    -Severity 'Critical' `
                    -Asset 'Domain Replication Rights' `
                    -Domain 'All' `
                    -EvidenceCount $dcsyncRows.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Restrict directory replication rights to only required built-in principals; investigate and remove any non-standard assignments.' `
                    -PolicyRef 'Microsoft AD security best practices; CIS AD (replication rights)' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    # 2) BH-PRIV-ACL-001 Shadow admin rights over privileged groups
    $privGroupPatterns = @('DOMAIN ADMINS', 'ENTERPRISE ADMINS', 'ADMINISTRATORS')
    $shadowRows = @()

    foreach ($g in $groups) {
        $gNameU = ($g.Name | ForEach-Object { $_.ToString().ToUpper() })
        $isPriv = $false
        foreach ($pat in $privGroupPatterns) {
            if ($gNameU -like "*$pat*") { $isPriv = $true; break }
        }
        if (-not $isPriv) { continue }
        if (-not $g.Aces) { continue }

        foreach ($ace in $g.Aces) {
            if ($ace.IsInherited -eq $true) { continue }
            if ($dangerRightsTier0 -notcontains $ace.RightName) { continue }

            $principal = Get-AcePrincipal -Ace $ace
            if (-not $principal) { continue }
            if (Is-ExcludedPrincipal -Principal $principal) { continue }

            $shadowRows += [pscustomobject]@{
                Domain        = $g.DomainFqdn
                GroupName     = $g.Name
                GroupSam      = $g.SamAccountName
                RightName     = $ace.RightName
                Principal     = $principal
                PrincipalType = $ace.PrincipalType
            }
        }
    }

    if ($shadowRows.Count -gt 0) {
        $evidencePath = Join-Path $bhDir ("BH-PRIV-ACL-001-shadow-admins-{0}.csv" -f $SnapshotTimestamp)
        $shadowRows | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-PRIV-ACL-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Non-standard principals with delegated control over privileged groups (shadow admins)'

        $crit = $false
        foreach ($r in $shadowRows) {
            $gn = $r.GroupName.ToString().ToUpper()
            if ($gn -like '*DOMAIN ADMINS*' -or $gn -like '*ENTERPRISE ADMINS*') { $crit = $true; break }
        }

        $findings.Add((New-Finding -FindingId 'BH-PRIV-ACL-001' `
                    -Category 'Identity' `
                    -Title 'Shadow admin rights detected over privileged groups' `
                    -Severity ($(if ($crit) { 'Critical' } else { 'High' })) `
                    -Asset 'Privileged Group Delegation' `
                    -Domain 'All' `
                    -EvidenceCount $shadowRows.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Remove non-standard delegated rights over privileged groups; validate delegation model and implement tiered administration.' `
                    -PolicyRef 'Microsoft Tier 0 guidance; CIS AD (privileged access)' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    # Helper: emit Tier-0 ACL finding for a set of objects
    function Add-Tier0AclFinding {
        param(
            [string]$FindingId,
            [string]$Title,
            [string]$Asset,
            [string]$EvidenceFilePrefix,
            [object[]]$Objects,
            [string]$Notes
        )

        $rows = @()
        foreach ($o in $Objects) {
            if (-not $o) { continue }
            if (-not $o.Aces) { continue }

            foreach ($ace in $o.Aces) {
                if ($ace.IsInherited -eq $true) { continue }
                if ($dangerRightsTier0 -notcontains $ace.RightName) { continue }

                $principal = Get-AcePrincipal -Ace $ace
                if (-not $principal) { continue }
                if (Is-ExcludedPrincipal -Principal $principal) { continue }

                $rows += [pscustomobject]@{
                    Domain            = $o.DomainFqdn
                    ObjectName        = $o.Name
                    DistinguishedName = $o.DistinguishedName
                    RightName         = $ace.RightName
                    Principal         = $principal
                    PrincipalType     = $ace.PrincipalType
                }
            }
        }

        if ($rows.Count -gt 0) {
            $evidencePath = Join-Path $bhDir ("{0}-{1}.csv" -f $EvidenceFilePrefix, $SnapshotTimestamp)
            $rows | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId $FindingId -EvidencePath $evidencePath -Domain 'All' -Notes $Notes

            $findings.Add((New-Finding -FindingId $FindingId `
                        -Category 'Identity' `
                        -Title $Title `
                        -Severity 'Critical' `
                        -Asset $Asset `
                        -Domain 'All' `
                        -EvidenceCount $rows.Count `
                        -EvidenceSource 'BloodHound' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation 'Remove non-standard delegated rights on Tier-0 objects; validate administrative boundaries and delegation model.' `
                        -PolicyRef 'Microsoft Tier 0 guidance; CIS AD (ACLs)' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }
    }

    # BH-TIER0-001 AdminSDHolder (with fallback)
    $adminSdObjs = Find-AdminSDHolderObjects -Containers $containers -Ous $ous -Domains $domains
    if ($adminSdObjs -and $adminSdObjs.Count -gt 0) {
        Add-Tier0AclFinding -FindingId 'BH-TIER0-001' `
            -Title 'Non-standard principals have dangerous rights on AdminSDHolder' `
            -Asset 'AdminSDHolder' `
            -EvidenceFilePrefix 'BH-TIER0-001-adminsdholder-dangerous-rights' `
            -Objects $adminSdObjs `
            -Notes 'Non-inherited dangerous ACEs on AdminSDHolder (containers preferred; OU/domain fallback supported)'
    } else {
        Write-SATLog -Message "AdminSDHolder not found in containers/ous/domains datasets for snapshot $SnapshotTimestamp (skipping BH-TIER0-001)" -LogPath $logPath
    }

    # 3) BH-TIER0-002 Domain root dangerous rights
    Add-Tier0AclFinding -FindingId 'BH-TIER0-002' `
        -Title 'Non-standard principals have dangerous rights on the domain root object' `
        -Asset 'Domain Root' `
        -EvidenceFilePrefix 'BH-TIER0-002-domainroot-dangerous-rights' `
        -Objects $domains `
        -Notes 'Non-inherited dangerous ACEs on domain root object(s)'

    # 4) BH-TIER0-003 Domain Controllers OU dangerous rights
    $dcOus = @($ous | Where-Object {
            ($_.Name -match 'Domain Controllers') -or
            ($_.DistinguishedName -and $_.DistinguishedName -match 'OU=Domain Controllers')
        })

    if ($dcOus.Count -gt 0) {
        Add-Tier0AclFinding -FindingId 'BH-TIER0-003' `
            -Title 'Non-standard principals have dangerous rights on the Domain Controllers OU' `
            -Asset 'Domain Controllers OU' `
            -EvidenceFilePrefix 'BH-TIER0-003-dc-ou-dangerous-rights' `
            -Objects $dcOus `
            -Notes 'Non-inherited dangerous ACEs on the Domain Controllers OU'
    } else {
        Write-SATLog -Message "Domain Controllers OU not found in ous dataset for snapshot $SnapshotTimestamp (skipping BH-TIER0-003)" -LogPath $logPath
    }

    # 5) BH-DELEG-002 RBCD configured on computer objects
    $rbcd = @($computers | Where-Object { $_.HasRBCD -eq $true })
    if ($rbcd.Count -gt 0) {
        $evidencePath = Join-Path $bhDir ("BH-DELEG-002-rbcd-configured-{0}.csv" -f $SnapshotTimestamp)
        $rbcd | Select-Object DomainFqdn, Name, SamAccountName, DistinguishedName, HasRBCD |
        Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-DELEG-002' -EvidencePath $evidencePath -Domain 'All' -Notes 'Computer objects with RBCD attribute present'

        $findings.Add((New-Finding -FindingId 'BH-DELEG-002' `
                    -Category 'Identity' `
                    -Title 'Resource-Based Constrained Delegation (RBCD) configured on computer objects' `
                    -Severity 'High' `
                    -Asset 'Delegation Settings' `
                    -Domain 'All' `
                    -EvidenceCount $rbcd.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Validate RBCD is required and restricted to approved principals; remove unnecessary configurations and monitor changes.' `
                    -PolicyRef 'Microsoft Kerberos delegation guidance; CIS AD (delegation)' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    # -----------------------------
    # Existing ACL finding BH-ACL-001 (kept, but UTF8 export)
    # -----------------------------
    $dangerousRights = @('GenericAll', 'WriteDacl', 'WriteOwner', 'GenericWrite', 'AllExtendedRights', 'AddMember', 'AddKeyCredentialLink', 'ForceChangePassword')
    $dangerousAces = New-Object System.Collections.Generic.List[object]

    foreach ($u in $users) {
        if (-not $u.Aces) { continue }
        foreach ($ace in $u.Aces) {
            if ($ace.IsInherited -eq $true) { continue }
            if ($dangerousRights -notcontains $ace.RightName) { continue }
            $dangerousAces.Add([pscustomobject]@{
                    Domain         = $u.DomainFqdn
                    ObjectType     = 'User'
                    ObjectName     = $u.Name
                    SamAccountName = $u.SamAccountName
                    RightName      = $ace.RightName
                    PrincipalType  = $ace.PrincipalType
                    PrincipalSid   = $ace.PrincipalSID
                    PrincipalName  = if ($ace.PSObject.Properties['PrincipalName']) { $ace.PrincipalName } else { $null }
                })
        }
    }

    foreach ($c in $computers) {
        if (-not $c.Aces) { continue }
        foreach ($ace in $c.Aces) {
            if ($ace.IsInherited -eq $true) { continue }
            if ($dangerousRights -notcontains $ace.RightName) { continue }
            $dangerousAces.Add([pscustomobject]@{
                    Domain         = $c.DomainFqdn
                    ObjectType     = 'Computer'
                    ObjectName     = $c.Name
                    SamAccountName = $c.SamAccountName
                    RightName      = $ace.RightName
                    PrincipalType  = $ace.PrincipalType
                    PrincipalSid   = $ace.PrincipalSID
                    PrincipalName  = if ($ace.PSObject.Properties['PrincipalName']) { $ace.PrincipalName } else { $null }
                })
        }
    }

    if ($dangerousAces.Count -gt 0) {
        $thresholdsAcl = Get-ThresholdSet -Name 'DangerousAcls' -Fallback @{ Low = 1; Medium = 10; High = 50 }
        $severity = Get-SeverityFromCount -Count $dangerousAces.Count -ThresholdSet $thresholdsAcl
        if ($severity -eq 'Informational') { $severity = 'Low' }

        $evidencePath = Join-Path $bhDir ("BH-ACL-001-dangerous-acls-{0}.csv" -f $SnapshotTimestamp)
        $dangerousAces | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-ACL-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Non-inherited dangerous ACEs on users/computers'

        $findings.Add((New-Finding -FindingId 'BH-ACL-001' `
                    -Category 'Identity' `
                    -Title 'Dangerous ACLs on AD objects' `
                    -Severity $severity `
                    -Asset 'Directory ACLs' `
                    -Domain 'All' `
                    -EvidenceCount $dangerousAces.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Review non-inherited powerful ACLs on users/computers and remove unnecessary rights.' `
                    -PolicyRef 'CIS AD (ACLs); Microsoft AD security best practices' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    # -----------------------------
    # BH-PATH-001 (profile gate: skip in LowImpact)
    # -----------------------------
    if ($Profile -eq 'LowImpact') {
        Write-SATLog -Message "Profile=LowImpact: skipping BH-PATH-001 session/local admin path analysis." -LogPath $logPath
    } else {
        $adminPathsSessions = New-Object System.Collections.Generic.List[object]
        $adminPathsLocalAdmins = New-Object System.Collections.Generic.List[object]
        foreach ($c in $computers) {
            if ($c.PrivilegedSessions) {
                foreach ($sess in $c.PrivilegedSessions) {
                    $adminPathsSessions.Add([pscustomobject]@{
                            Domain         = $c.DomainFqdn
                            ComputerName   = $c.Name
                            SamAccountName = $c.SamAccountName
                            SessionUserId  = if ($sess.PSObject.Properties['UserId']) { $sess.UserId } else { $sess }
                        })
                }
            }

            $localGroups = $null
            if ($c.LocalGroups) {
                if ($c.LocalGroups.PSObject.Properties['Results']) {
                    $localGroups = $c.LocalGroups.Results
                } elseif ($c.LocalGroups -is [array]) {
                    $localGroups = $c.LocalGroups
                } else {
                    $localGroups = @($c.LocalGroups)
                }
            }

            if ($localGroups) {
                foreach ($lg in $localGroups) {
                    $groupName = if ($lg.PSObject.Properties['Name']) { [string]$lg.Name } else { $null }
                    if (-not $groupName) { continue }
                    if ($groupName -notmatch '(?i)administrators') { continue }

                    $members = $null
                    if ($lg.PSObject.Properties['Members']) {
                        $members = $lg.Members
                    } elseif ($lg.PSObject.Properties['Results']) {
                        $members = $lg.Results
                    }

                    if (-not $members) { continue }

                    foreach ($m in $members) {
                        $adminPathsLocalAdmins.Add([pscustomobject]@{
                                Domain         = $c.DomainFqdn
                                ComputerName   = $c.Name
                                SamAccountName = $c.SamAccountName
                                GroupName      = $groupName
                                MemberName     = if ($m.PSObject.Properties['Name']) { [string]$m.Name } else { $null }
                                MemberType     = if ($m.PSObject.Properties['ObjectType']) { [string]$m.ObjectType } else { $null }
                                MemberId       = if ($m.PSObject.Properties['ObjectIdentifier']) { [string]$m.ObjectIdentifier } else { $null }
                            })
                    }
                }
            }
        }

        $adminPathsAll = @($adminPathsSessions + $adminPathsLocalAdmins)

        if ($adminPathsAll.Count -gt 0) {
            $thresholdsPaths = Get-ThresholdSet -Name 'AdminToComputerPaths' -Fallback @{ Low = 1; Medium = 5; High = 20 }
            $severity = Get-SeverityFromCount -Count $adminPathsAll.Count -ThresholdSet $thresholdsPaths

            $evidenceRef = $null

            if ($adminPathsSessions.Count -gt 0) {
                $sessionsPath = Join-Path $bhDir ("BH-PATH-001-admin-to-computer-sessions-{0}.csv" -f $SnapshotTimestamp)
                $adminPathsSessions | Export-Csv -Path $sessionsPath -NoTypeInformation -Encoding UTF8
                Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-PATH-001' -EvidencePath $sessionsPath -Domain 'All' -Notes 'Privileged sessions on computers'
                if (-not $evidenceRef) { $evidenceRef = Split-Path $sessionsPath -Leaf }
            }

            if ($adminPathsLocalAdmins.Count -gt 0) {
                $localAdminPath = Join-Path $bhDir ("BH-PATH-001-local-admin-rights-{0}.csv" -f $SnapshotTimestamp)
                $adminPathsLocalAdmins | Export-Csv -Path $localAdminPath -NoTypeInformation -Encoding UTF8
                Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-PATH-001' -EvidencePath $localAdminPath -Domain 'All' -Notes 'Local Administrators group membership'
                if (-not $evidenceRef) { $evidenceRef = Split-Path $localAdminPath -Leaf }
            }

            $findings.Add((New-Finding -FindingId 'BH-PATH-001' `
                        -Category 'Identity' `
                        -Title 'Admin-to-computer paths (privileged sessions and local admin rights)' `
                        -Severity $severity `
                        -Asset 'Privileged Sessions' `
                        -Domain 'All' `
                        -EvidenceCount $adminPathsAll.Count `
                        -EvidenceSource 'BloodHound' `
                        -EvidenceRef $evidenceRef `
                        -Recommendation 'Reduce privileged session exposure on endpoints and servers; use tiered admin workstations.' `
                        -PolicyRef 'Microsoft Tier 0 guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }
    }

    # -----------------------------
    # Remaining existing findings (unchanged, but UTF8 exports)
    # -----------------------------
    $asrepUsers = @($users | Where-Object { $_.DontRequirePreauth -eq $true })
    if ($asrepUsers.Count -gt 0) {
        $thresholdsAsrep = Get-ThresholdSet -Name 'AsrepRoastableUsers' -Fallback @{ Low = 1; Medium = 3; High = 10 }
        $severity = Get-SeverityFromCount -Count $asrepUsers.Count -ThresholdSet $thresholdsAsrep

        $evidencePath = Join-Path $bhDir ("BH-ACCT-002-asrep-roastable-{0}.csv" -f $SnapshotTimestamp)
        $asrepUsers | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-ACCT-002' -EvidencePath $evidencePath -Domain 'All' -Notes 'Users with pre-authentication disabled (AS-REP roastable)'

        $findings.Add((New-Finding -FindingId 'BH-ACCT-002' `
                    -Category 'Identity' `
                    -Title 'AS-REP roastable accounts (pre-auth disabled)' `
                    -Severity $severity `
                    -Asset 'User Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $asrepUsers.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Enable pre-authentication for user accounts unless explicitly required. Review legacy apps and exceptions.' `
                    -PolicyRef 'CIS AD (Kerberos); Microsoft Kerberos guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    $pwdNotReqUsers = @($users | Where-Object { $_.PasswordNotRequired -eq $true })
    if ($pwdNotReqUsers.Count -gt 0) {
        $thresholdsPwdReq = Get-ThresholdSet -Name 'PasswordNotRequiredUsers' -Fallback @{ Low = 1; Medium = 5; High = 20 }
        $severity = Get-SeverityFromCount -Count $pwdNotReqUsers.Count -ThresholdSet $thresholdsPwdReq

        $evidencePath = Join-Path $bhDir ("BH-ACCT-003-password-not-required-{0}.csv" -f $SnapshotTimestamp)
        $pwdNotReqUsers | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-ACCT-003' -EvidencePath $evidencePath -Domain 'All' -Notes 'Users with PasswordNotRequired'

        $findings.Add((New-Finding -FindingId 'BH-ACCT-003' `
                    -Category 'Identity' `
                    -Title 'Accounts with PasswordNotRequired flag' `
                    -Severity $severity `
                    -Asset 'User Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $pwdNotReqUsers.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Disable PasswordNotRequired on user accounts and review legacy configurations.' `
                    -PolicyRef 'CIS AD (password policy); Microsoft identity guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    $lapsMissing = @($computers | Where-Object { $_.HasLaps -eq $false })
    if ($lapsMissing.Count -gt 0) {
        $thresholdsLaps = Get-ThresholdSet -Name 'LapsMissingComputers' -Fallback @{ Low = 10; Medium = 50; High = 200 }
        $severity = Get-SeverityFromCount -Count $lapsMissing.Count -ThresholdSet $thresholdsLaps

        $evidencePath = Join-Path $bhDir ("BH-COMP-001-laps-missing-{0}.csv" -f $SnapshotTimestamp)
        $lapsMissing | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-COMP-001' -EvidencePath $evidencePath -Domain 'All' -Notes 'Computers without LAPS/Windows LAPS enabled'

        $findings.Add((New-Finding -FindingId 'BH-COMP-001' `
                    -Category 'Identity' `
                    -Title 'LAPS not enabled on computer accounts' `
                    -Severity $severity `
                    -Asset 'Computer Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $lapsMissing.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Enable Windows LAPS or LAPS for domain-joined computers and secure read permissions.' `
                    -PolicyRef 'CIS AD (LAPS); Microsoft LAPS guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    $staleComputers = @()
    foreach ($c in $computers) {
        $days = Get-DaysSince -TimestampValue $c.LastLogonTimestamp
        if ($null -eq $days -or $days -ge 120) {
            $staleComputers += [pscustomobject]@{
                Domain          = $c.DomainFqdn
                ComputerName    = $c.Name
                SamAccountName  = $c.SamAccountName
                LastLogonDays   = $days
                Enabled         = $c.Enabled
                IsDc            = $c.IsDc
                OperatingSystem = $c.OperatingSystem
            }
        }
    }

    if ($staleComputers.Count -gt 0) {
        $thresholdsStaleComp = Get-ThresholdSet -Name 'StaleComputers' -Fallback @{ Low = 10; Medium = 50; High = 200 }
        $severity = Get-SeverityFromCount -Count $staleComputers.Count -ThresholdSet $thresholdsStaleComp

        $evidencePath = Join-Path $bhDir ("BH-COMP-002-stale-computers-{0}.csv" -f $SnapshotTimestamp)
        $staleComputers | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-COMP-002' -EvidencePath $evidencePath -Domain 'All' -Notes 'Computers inactive or never logged on (>=120 days)'

        $findings.Add((New-Finding -FindingId 'BH-COMP-002' `
                    -Category 'Identity' `
                    -Title 'Stale computer accounts' `
                    -Severity $severity `
                    -Asset 'Computer Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $staleComputers.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Review and disable or remove computer accounts inactive for 120+ days; validate servers before disabling.' `
                    -PolicyRef 'CIS AD (account hygiene); Microsoft identity guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    $disabledSpnAccounts = @($users | Where-Object { $_.Enabled -eq $false -and ($_.HasSpn -or $_.SpnCount -gt 0) })
    if ($disabledSpnAccounts.Count -gt 0) {
        $thresholdsDisabled = Get-ThresholdSet -Name 'DisabledSpnAccounts' -Fallback @{ Low = 1; Medium = 5; High = 20 }
        $severity = Get-SeverityFromCount -Count $disabledSpnAccounts.Count -ThresholdSet $thresholdsDisabled

        $evidencePath = Join-Path $bhDir ("BH-SVC-002-disabled-spn-accounts-{0}.csv" -f $SnapshotTimestamp)
        $disabledSpnAccounts | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'BH-SVC-002' -EvidencePath $evidencePath -Domain 'All' -Notes 'Disabled accounts with SPNs'

        $findings.Add((New-Finding -FindingId 'BH-SVC-002' `
                    -Category 'Identity' `
                    -Title 'Disabled accounts with SPNs present' `
                    -Severity $severity `
                    -Asset 'Service Accounts' `
                    -Domain 'All' `
                    -EvidenceCount $disabledSpnAccounts.Count `
                    -EvidenceSource 'BloodHound' `
                    -EvidenceRef (Split-Path $evidencePath -Leaf) `
                    -Recommendation 'Review disabled SPN accounts to ensure they are decommissioned and not re-enabled.' `
                    -PolicyRef 'CIS AD (account hygiene); Microsoft identity guidance' `
                    -Profile $Profile `
                    -Tool 'Security.Assessment.Toolkit'))
    }

    Export-SATFindings -AssessmentPath $assessmentPath -Findings $findings -EvidenceIndex $evidenceIndex -Scope 'BloodHound' | Out-Null

    Write-SATLog -Message "Invoke-SATBloodHoundAnalysis completed. OutputPath=$assessmentPath" -LogPath $logPath
    $evidenceFiles = @($evidenceIndex | ForEach-Object { Join-Path $bhDir $_.EvidenceFile })
    return [pscustomobject]@{
        AssessmentPath = $assessmentPath
        Scope          = 'BloodHound'
        EvidenceFiles  = $evidenceFiles
        FindingIds     = @($findings | Select-Object -ExpandProperty FindingId)
        Findings       = @($findings)
    }
}
