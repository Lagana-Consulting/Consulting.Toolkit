function Get-AdSecurityFindings {
    [CmdletBinding()]
    param (
        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$ForestName,

        [string]$DomainFqdn,

        [string]$Server,

        [string]$OutputRoot,

        [int]$StaleDays = 90,

        [int]$StaleComputerDays = 90,

        [string]$ConfigRoot,

        [hashtable]$CommandMap
    )

    Set-StrictMode -Version Latest

    $defaults = @{
        AdDomains                = 'Get-AdAdDomains'
        DomainContext            = 'Get-AdAdDomainContext'
        PrivilegedAccounts       = 'Get-AdPrivilegedAccounts'
        AdUsers                  = 'Get-AdAdUsers'
        AdComputers              = 'Get-AdAdComputers'
        ServiceAccountCandidates = 'Get-AdServiceAccountCandidates'
        UnconstrainedDelegation  = 'Get-AdUnconstrainedDelegation'
        WeakPasswordPolicies     = 'Get-AdWeakPasswordPolicies'
        GpoUserRights            = 'Get-AdGpoUserRightsAssignments'
    }

    if ($CommandMap) {
        foreach ($key in $CommandMap.Keys) {
            $defaults[$key] = $CommandMap[$key]
        }
    }

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $OutputRoot) {
        $OutputRoot = Get-SATOutputRootInternal
    }

    if (-not (Test-Path $OutputRoot)) {
        New-Item -Path $OutputRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $assessmentPath = Join-Path $OutputRoot $timestamp
    New-Item -Path $assessmentPath -ItemType Directory -Force | Out-Null

    Import-Module Migration.Toolkit -ErrorAction Stop

    $logsDir = Join-Path $assessmentPath 'Logs'
    if (-not (Test-Path $logsDir)) {
        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
    }

    $logPath = Join-Path $logsDir 'RunLog.txt'
    Write-AdLog -Path $logPath -Level INFO -Message "Get-AdSecurityFindings started. Profile=$Profile"

    $evidenceRoot = Join-Path $assessmentPath 'Evidence'
    $evidenceAdDir = Join-Path $evidenceRoot 'AD'
    if (-not (Test-Path $evidenceAdDir)) {
        New-Item -Path $evidenceAdDir -ItemType Directory -Force | Out-Null
    }

    foreach ($key in $defaults.Keys) {
        $commandName = $defaults[$key]
        if (-not $commandName) {
            continue
        }

        if ($key -eq 'DomainContext') {
            continue
        }

        $command = Get-Command -Name $commandName -Module Migration.Toolkit -ErrorAction SilentlyContinue
        if (-not $command) {
            throw "Required Migration.Toolkit command '$commandName' not found. Provide -CommandMap to override." 
        }
    }

    if (-not $ConfigRoot) {
        $ConfigRoot = Join-Path $moduleRoot 'config'
    }

    $thresholdsPath = Join-Path $ConfigRoot 'thresholds.json'
    $severityMapPath = Join-Path $ConfigRoot 'severity_map.json'

    $thresholds = [pscustomobject]@{}
    if (Test-Path $thresholdsPath) {
        $thresholds = Get-Content -Path $thresholdsPath -Raw | ConvertFrom-Json
    }

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

    function Get-ThresholdSet {
        param (
            [string]$Name,
            [hashtable]$Fallback = @{ Low = 1; Medium = 3; High = 10 }
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

        if ($Count -ge $ThresholdSet.High) {
            return 'High'
        }
        if ($Count -ge $ThresholdSet.Medium) {
            return 'Medium'
        }
        if ($Count -ge $ThresholdSet.Low) {
            return 'Low'
        }
        return 'Informational'
    }

    function Get-PropertyValue {
        param (
            [object]$Object,
            [string[]]$Names
        )

        if (-not $Object) {
            return $null
        }

        foreach ($name in $Names) {
            if ($Object.PSObject.Properties.Name -contains $name) {
                return $Object.$name
            }
        }
        return $null
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
            $riskScore = [int]$severityMap[$Severity]
        }

        return [pscustomobject]@{
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

    $findings = New-Object System.Collections.Generic.List[object]
    $evidenceIndex = New-Object System.Collections.Generic.List[object]
    $summaryData = @{
        'AD-PRIV-001'  = New-Object System.Collections.Generic.List[object]
        'AD-ACCT-001'  = New-Object System.Collections.Generic.List[object]
        'AD-ACCT-002'  = New-Object System.Collections.Generic.List[object]
        'AD-DELEG-001' = New-Object System.Collections.Generic.List[object]
        'AD-POL-001'   = New-Object System.Collections.Generic.List[object]
        'AD-SVC-001'   = New-Object System.Collections.Generic.List[object]
        'AD-PRIV-002'  = New-Object System.Collections.Generic.List[object]
        'AD-COMP-001'  = New-Object System.Collections.Generic.List[object]
        'AD-GPO-001'   = New-Object System.Collections.Generic.List[object]
    }

    $module = Get-Module -Name Migration.Toolkit
    $domains = if ($DomainFqdn) { @($DomainFqdn) } else { & $defaults.AdDomains -ForestName $ForestName -Server $Server }

    foreach ($domain in $domains) {
        $domainTag = $domain -replace '[^a-zA-Z0-9_-]', '_'
        $context = & $module { param($d, $s, $log) Get-AdAdDomainContext -DomainFqdn $d -Server $s -LogPath $log } $domain $Server $logPath

        $privilegedAccounts = & $defaults.PrivilegedAccounts -DomainContext $context
        $privilegedInGroups = @($privilegedAccounts | Where-Object { $_.InPrivGroups -eq $true })
        $domainAdmins = $privilegedInGroups | Where-Object { $_.PrivGroups -match '(?i)Domain Admins' }
        $enterpriseAdmins = $privilegedInGroups | Where-Object { $_.PrivGroups -match '(?i)Enterprise Admins' }

        $domainCount = @($domainAdmins).Count
        $enterpriseCount = @($enterpriseAdmins).Count

        $domainThresholds = Get-ThresholdSet -Name 'DomainAdmins' -Fallback @{ Low = 2; Medium = 5; High = 10 }
        $enterpriseThresholds = Get-ThresholdSet -Name 'EnterpriseAdmins' -Fallback $domainThresholds

        if (($domainCount -ge $domainThresholds.Low) -or ($enterpriseCount -ge $enterpriseThresholds.Low)) {
            $domainSeverity = Get-SeverityFromCount -Count $domainCount -ThresholdSet $domainThresholds
            $enterpriseSeverity = Get-SeverityFromCount -Count $enterpriseCount -ThresholdSet $enterpriseThresholds
            $severity = if ($severityMap[$domainSeverity] -ge $severityMap[$enterpriseSeverity]) { $domainSeverity } else { $enterpriseSeverity }

            $evidencePath = Join-Path $evidenceAdDir ("AD-PRIV-001-privileged-members-{0}.csv" -f $domainTag)
            $privilegedAccounts | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-PRIV-001' -EvidencePath $evidencePath -Domain $domain -Notes 'Privileged group membership (recursive)'

            $summaryData['AD-PRIV-001'].Add([pscustomobject]@{
                    Domain                = $domain
                    DomainAdminsCount     = $domainCount
                    EnterpriseAdminsCount = $enterpriseCount
                    Severity              = $severity
                })

            $findings.Add((New-Finding -FindingId 'AD-PRIV-001' `
                        -Category 'Identity' `
                        -Title 'Excessive membership in Domain/Enterprise Admins' `
                        -Severity $severity `
                        -Asset 'Privileged Groups' `
                        -Domain $domain `
                        -EvidenceCount @($privilegedAccounts).Count `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation 'Reduce privileged group membership to the minimum required. Use JIT/JEA for admin access and limit standing privileges.' `
                        -PolicyRef 'CIS AD (privileged groups); Microsoft Tier 0 guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }

        $serviceCandidates = & $defaults.ServiceAccountCandidates -DomainContext $context
        $pneUsers = @($serviceCandidates | Where-Object { $_.PasswordNeverExpires -eq $true })
        if ($pneUsers.Count -gt 0) {
            $pneThresholds = Get-ThresholdSet -Name 'PasswordNeverExpires' -Fallback @{ Low = 1; Medium = 5; High = 20 }
            $pneCount = $pneUsers.Count
            $pneSeverity = Get-SeverityFromCount -Count $pneCount -ThresholdSet $pneThresholds

            $evidencePath = Join-Path $evidenceAdDir ("AD-ACCT-001-password-never-expires-{0}.csv" -f $domainTag)
            $pneUsers | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-ACCT-001' -EvidencePath $evidencePath -Domain $domain -Notes 'Accounts with PasswordNeverExpires'

            $summaryData['AD-ACCT-001'].Add([pscustomobject]@{
                    Domain   = $domain
                    Count    = $pneCount
                    Severity = $pneSeverity
                })

            $findings.Add((New-Finding -FindingId 'AD-ACCT-001' `
                        -Category 'Identity' `
                        -Title 'Accounts with PasswordNeverExpires enabled' `
                        -Severity $pneSeverity `
                        -Asset 'User Accounts' `
                        -Domain $domain `
                        -EvidenceCount $pneCount `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation 'Disable PasswordNeverExpires for user accounts. Use managed service accounts or documented exceptions.' `
                        -PolicyRef 'CIS AD (password policy); Microsoft identity guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }

        $allUsers = & $defaults.AdUsers -DomainContext $context
        $svcLookup = @{}
        foreach ($svc in $serviceCandidates) {
            if ($svc.SamAccountName) {
                $svcLookup[$svc.SamAccountName] = $svc
            }
        }

        $kerberoastable = @()
        foreach ($user in $allUsers) {
            if (-not $user.SPNCount -or [int]$user.SPNCount -le 0) {
                continue
            }

            $svcInfo = $null
            if ($svcLookup.ContainsKey($user.SamAccountName)) {
                $svcInfo = $svcLookup[$user.SamAccountName]
            }

            $kerberoastable += [pscustomobject]@{
                DomainFqdn           = $user.DomainFqdn
                SamAccountName       = $user.SamAccountName
                UserPrincipalName    = $user.UserPrincipalName
                SPNCount             = $user.SPNCount
                EncryptionTypes      = $user.EncryptionTypes
                EncryptionRisk       = $user.EncryptionRisk
                PasswordNeverExpires = if ($svcInfo) { $svcInfo.PasswordNeverExpires } else { $null }
                LastLogonDays        = $user.LastLogonDays
                PasswordAgeDays      = $user.PasswordAgeDays
            }
        }

        if ($kerberoastable.Count -gt 0) {
            $kerbThresholds = Get-ThresholdSet -Name 'KerberoastableAccounts' -Fallback @{ Low = 1; Medium = 5; High = 20 }
            $kerbCount = $kerberoastable.Count
            $kerbSeverity = Get-SeverityFromCount -Count $kerbCount -ThresholdSet $kerbThresholds
            $weakKerbCount = @($kerberoastable | Where-Object { $_.EncryptionTypes -and $_.EncryptionTypes -notmatch 'AES' }).Count

            if ($weakKerbCount -gt 0 -and $severityMap['High'] -gt $severityMap[$kerbSeverity]) {
                $kerbSeverity = 'High'
            }

            $evidencePath = Join-Path $evidenceAdDir ("AD-SVC-001-kerberoastable-{0}.csv" -f $domainTag)
            $kerberoastable | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-SVC-001' -EvidencePath $evidencePath -Domain $domain -Notes 'Accounts with SPNs (kerberoastable baseline)'

            $summaryData['AD-SVC-001'].Add([pscustomobject]@{
                    Domain       = $domain
                    Count        = $kerbCount
                    WeakEncCount = $weakKerbCount
                    Severity     = $kerbSeverity
                })

            $findings.Add((New-Finding -FindingId 'AD-SVC-001' `
                        -Category 'Identity' `
                        -Title 'Kerberoastable service accounts (SPNs present)' `
                        -Severity $kerbSeverity `
                        -Asset 'Service Accounts' `
                        -Domain $domain `
                        -EvidenceCount $kerbCount `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation 'Review accounts with SPNs. Enforce AES-only Kerberos, rotate passwords, and use managed service accounts where possible.' `
                        -PolicyRef 'CIS AD (Kerberos); Microsoft Kerberos hardening guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }

        $privSam = @($privilegedAccounts | Where-Object { $_.SamAccountName } | Select-Object -ExpandProperty SamAccountName -Unique)
        $privLookup = @{}
        foreach ($sam in $privSam) { $privLookup[$sam] = $true }
        $privUsers = @($allUsers | Where-Object { $privLookup.ContainsKey($_.SamAccountName) })
        $stalePriv = @($privUsers | Where-Object { -not $_.LastLogonDays -or [int]$_.LastLogonDays -ge $StaleDays })

        if ($stalePriv.Count -gt 0) {
            $staleThresholds = Get-ThresholdSet -Name 'StalePrivileged' -Fallback @{ Low = 1; Medium = 3; High = 10 }
            $staleCount = $stalePriv.Count
            $staleSeverity = Get-SeverityFromCount -Count $staleCount -ThresholdSet $staleThresholds

            $evidencePath = Join-Path $evidenceAdDir ("AD-ACCT-002-stale-privileged-{0}.csv" -f $domainTag)
            $stalePriv | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-ACCT-002' -EvidencePath $evidencePath -Domain $domain -Notes ("Privileged accounts inactive >= {0} days" -f $StaleDays)

            $summaryData['AD-ACCT-002'].Add([pscustomobject]@{
                    Domain    = $domain
                    Count     = $staleCount
                    Severity  = $staleSeverity
                    StaleDays = $StaleDays
                })

            $findings.Add((New-Finding -FindingId 'AD-ACCT-002' `
                        -Category 'Identity' `
                        -Title 'Stale privileged accounts' `
                        -Severity $staleSeverity `
                        -Asset 'Privileged Accounts' `
                        -Domain $domain `
                        -EvidenceCount $staleCount `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation "Review privileged accounts inactive for $StaleDays days. Disable or remove access and document exceptions." `
                        -PolicyRef 'CIS AD (privileged access); Microsoft Tier 0 guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }

        $orphanedProtected = @($privilegedAccounts | Where-Object { $_.AdminCount -eq $true -and $_.InPrivGroups -eq $false })
        if ($orphanedProtected.Count -gt 0) {
            $orphanThresholds = Get-ThresholdSet -Name 'OrphanedAdminCount' -Fallback @{ Low = 1; Medium = 3; High = 10 }
            $orphanCount = $orphanedProtected.Count
            $orphanSeverity = Get-SeverityFromCount -Count $orphanCount -ThresholdSet $orphanThresholds

            $evidencePath = Join-Path $evidenceAdDir ("AD-PRIV-002-orphaned-admincount-{0}.csv" -f $domainTag)
            $orphanedProtected | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-PRIV-002' -EvidencePath $evidencePath -Domain $domain -Notes 'AdminCount=1 without current privileged group membership'

            $summaryData['AD-PRIV-002'].Add([pscustomobject]@{
                    Domain   = $domain
                    Count    = $orphanCount
                    Severity = $orphanSeverity
                })

            $findings.Add((New-Finding -FindingId 'AD-PRIV-002' `
                        -Category 'Identity' `
                        -Title 'Orphaned protected accounts (AdminCount=1 without privileged group membership)' `
                        -Severity $orphanSeverity `
                        -Asset 'Privileged Accounts' `
                        -Domain $domain `
                        -EvidenceCount $orphanCount `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation 'Review AdminCount=1 accounts not in privileged groups. Remove AdminCount or re-evaluate group membership.' `
                        -PolicyRef 'CIS AD (privileged access); Microsoft Tier 0 guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }

        $unconstrained = & $defaults.UnconstrainedDelegation -DomainContext $context
        if ($unconstrained) {
            $evidencePath = Join-Path $evidenceAdDir ("AD-DELEG-001-unconstrained-delegation-{0}.csv" -f $domainTag)
            $unconstrained | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-DELEG-001' -EvidencePath $evidencePath -Domain $domain -Notes 'Trusted for delegation flag'

            $summaryData['AD-DELEG-001'].Add([pscustomobject]@{
                    Domain = $domain
                    Count  = @($unconstrained).Count
                })

            $findings.Add((New-Finding -FindingId 'AD-DELEG-001' `
                        -Category 'Identity' `
                        -Title 'Unconstrained delegation enabled' `
                        -Severity 'High' `
                        -Asset 'Delegation Settings' `
                        -Domain $domain `
                        -EvidenceCount @($unconstrained).Count `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation 'Replace unconstrained delegation with constrained or resource-based delegation and restrict affected principals.' `
                        -PolicyRef 'CIS AD (delegation); Microsoft Kerberos delegation guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }

        $weakPolicies = & $defaults.WeakPasswordPolicies -DomainContext $context
        if ($weakPolicies -and $weakPolicies.Count -gt 0) {
            $evidencePath = Join-Path $evidenceAdDir ("AD-POL-001-password-policy-{0}.json" -f $domainTag)
            $weakPolicies | ConvertTo-Json -Depth 6 | Set-Content -Path $evidencePath
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-POL-001' -EvidencePath $evidencePath -Domain $domain -Notes 'Default and FGPP policy gaps'

            $summaryData['AD-POL-001'].Add([pscustomobject]@{
                    Domain          = $domain
                    WeakPolicyCount = @($weakPolicies).Count
                    HighRiskCount   = @($weakPolicies | Where-Object { $_.RiskLevel -eq 'High' }).Count
                    MediumRiskCount = @($weakPolicies | Where-Object { $_.RiskLevel -eq 'Medium' }).Count
                    LowRiskCount    = @($weakPolicies | Where-Object { $_.RiskLevel -eq 'Low' }).Count
                    Severity        = $policySeverity
                })

            $policySeverity = if (($weakPolicies | Where-Object { $_.RiskLevel -eq 'High' }).Count -gt 0) {
                'High'
            } elseif (($weakPolicies | Where-Object { $_.RiskLevel -eq 'Medium' }).Count -gt 0) {
                'Medium'
            } else {
                'Low'
            }

            $findings.Add((New-Finding -FindingId 'AD-POL-001' `
                        -Category 'Identity' `
                        -Title 'Weak or inconsistent password policy (default + FGPP)' `
                        -Severity $policySeverity `
                        -Asset 'Password Policy' `
                        -Domain $domain `
                        -EvidenceCount @($weakPolicies).Count `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation 'Align default and FGPP policies to strong baselines (length, complexity, and reasonable max age). Avoid weaker exceptions.' `
                        -PolicyRef 'CIS AD (password policy); Microsoft identity guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }

        $denyRights = & $defaults.GpoUserRights -DomainContext $context -RightName @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight') -LogPath $logPath
        if ($denyRights -and $denyRights.Count -gt 0) {
            $tier0Groups = @(
                'Enterprise Admins',
                'Schema Admins',
                'Enterprise Key Admins',
                'Key Admins',
                'Domain Admins',
                'Administrators',
                'Domain Controllers',
                'Read-only Domain Controllers',
                'Enterprise Read-only Domain Controllers',
                'Group Policy Creator Owners',
                'Protected Users',
                'Cert Publishers',
                'Account Operators',
                'Server Operators',
                'Backup Operators',
                'Print Operators',
                'DNSAdmins'
            )
            $rights = @{}
            foreach ($row in $denyRights) {
                if (-not $rights.ContainsKey($row.RightName)) {
                    $rights[$row.RightName] = New-Object System.Collections.Generic.List[string]
                }

                if ($row.Members) {
                    $members = $row.Members -split ';'
                    foreach ($member in $members) {
                        $m = $member.Trim()
                        if ($m) { $rights[$row.RightName].Add($m) }
                    }
                }
            }

            $gapRows = New-Object System.Collections.Generic.List[object]
            foreach ($right in @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight')) {
                $assigned = @()
                if ($rights.ContainsKey($right)) {
                    $assigned = @($rights[$right] | Sort-Object -Unique)
                }

                $missing = @()
                foreach ($g in $tier0Groups) {
                    if ($assigned -notcontains $g -and $assigned -notcontains ("{0}\\{1}" -f $context.NetBiosName, $g)) {
                        $missing += $g
                    }
                }

                if ($missing.Count -gt 0) {
                    $gapRows.Add([pscustomobject]@{
                            Domain        = $domain
                            RightName     = $right
                            MissingGroups = ($missing -join ';')
                            Assigned      = ($assigned -join ';')
                        })
                }
            }

            if ($gapRows.Count -gt 0) {
                $evidencePath = Join-Path $evidenceAdDir ("AD-GPO-001-deny-logon-gaps-{0}.csv" -f $domainTag)
                $gapRows | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
                Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-GPO-001' -EvidencePath $evidencePath -Domain $domain -Notes 'Tier-0 groups missing from deny logon locally/RDP rights'

                $summaryData['AD-GPO-001'].Add([pscustomobject]@{
                        Domain   = $domain
                        GapCount = $gapRows.Count
                    })

                $findings.Add((New-Finding -FindingId 'AD-GPO-001' `
                            -Category 'Identity' `
                            -Title 'Tier-0 deny logon locally/RDP gaps' `
                            -Severity 'Medium' `
                            -Asset 'GPO User Rights' `
                            -Domain $domain `
                            -EvidenceCount $gapRows.Count `
                            -EvidenceSource 'GroupPolicy' `
                            -EvidenceRef (Split-Path $evidencePath -Leaf) `
                            -Recommendation 'Deny interactive and RDP logon for Tier-0 groups via GPOs. Validate with change control.' `
                            -PolicyRef 'CIS AD (user rights); Microsoft Tier 0 guidance' `
                            -Profile $Profile `
                            -Tool 'Security.Assessment.Toolkit'))
            }
        }

        $computers = & $defaults.AdComputers -DomainContext $context
        $staleComputers = @($computers | Where-Object { $_.LastLogonDays -and [int]$_.LastLogonDays -ge $StaleComputerDays })
        if ($staleComputers.Count -gt 0) {
            $serverCount = @($staleComputers | Where-Object { $_.IsServer -eq $true }).Count
            $workstationCount = @($staleComputers | Where-Object { $_.IsServer -eq $false }).Count

            $compThresholds = Get-ThresholdSet -Name 'StaleComputers' -Fallback @{ Low = 10; Medium = 50; High = 200 }
            $compCount = $staleComputers.Count
            $compSeverity = Get-SeverityFromCount -Count $compCount -ThresholdSet $compThresholds

            $evidencePath = Join-Path $evidenceAdDir ("AD-COMP-001-stale-computers-{0}.csv" -f $domainTag)
            $staleComputers | Export-Csv -Path $evidencePath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'AD-COMP-001' -EvidencePath $evidencePath -Domain $domain -Notes ("Computers inactive >= {0} days" -f $StaleComputerDays)

            $summaryData['AD-COMP-001'].Add([pscustomobject]@{
                    Domain           = $domain
                    Count            = $compCount
                    ServerCount      = $serverCount
                    WorkstationCount = $workstationCount
                    Severity         = $compSeverity
                    StaleDays        = $StaleComputerDays
                })

            $findings.Add((New-Finding -FindingId 'AD-COMP-001' `
                        -Category 'Identity' `
                        -Title 'Stale computer accounts' `
                        -Severity $compSeverity `
                        -Asset 'Computer Accounts' `
                        -Domain $domain `
                        -EvidenceCount $compCount `
                        -EvidenceSource 'ActiveDirectory' `
                        -EvidenceRef (Split-Path $evidencePath -Leaf) `
                        -Recommendation "Review and disable or remove computer accounts inactive for $StaleComputerDays days. Validate servers before disabling." `
                        -PolicyRef 'CIS AD (account hygiene); Microsoft identity guidance' `
                        -Profile $Profile `
                        -Tool 'Security.Assessment.Toolkit'))
        }
    }

    foreach ($findingId in $summaryData.Keys) {
        $rows = $summaryData[$findingId]
        if ($rows -and $rows.Count -gt 0) {
            $summaryPath = Join-Path $evidenceAdDir ("{0}-summary.csv" -f $findingId)
            $rows | Export-Csv -Path $summaryPath -NoTypeInformation -Encoding UTF8
            Add-EvidenceIndex -Index $evidenceIndex -FindingId $findingId -EvidencePath $summaryPath -Domain 'All' -Notes 'Summary by domain'
        }
    }

    Export-SATFindings -AssessmentPath $assessmentPath -Findings $findings -EvidenceIndex $evidenceIndex -Scope 'AD' | Out-Null

    Write-AdLog -Path $logPath -Level INFO -Message "Get-AdSecurityFindings completed. OutputPath=$assessmentPath"
    return [pscustomobject]@{
        AssessmentPath = $assessmentPath
        Scope          = 'AD'
        EvidenceFiles  = @()
        FindingIds     = @($findings | Select-Object -ExpandProperty FindingId)
        Findings       = @($findings)
    }
}
