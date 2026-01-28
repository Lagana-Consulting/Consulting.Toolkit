function New-AdAssessmentReport {
    <#
    .SYNOPSIS
    Generate an HTML assessment report from AD discovery outputs.

    .DESCRIPTION
    Creates a professional executive-level HTML report from discovery CSVs, including
    metrics, risk overview, per-domain summaries, and remediation recommendations.

    .PARAMETER DiscoveryOutputPath
    Path to the discovery output folder containing CSV files and domain subfolders.

    .PARAMETER OutputPath
    Path where the HTML report will be saved. Defaults to discovery root with timestamp.

    .EXAMPLE
    New-AdAssessmentReport -DiscoveryOutputPath "C:\scripts\Reports\ADOnly_20260121-130000"

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$DiscoveryOutputPath,

        [string]$OutputPath
    )

    # Default output to discovery root with timestamp
    if (-not $OutputPath) {
        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $OutputPath = Join-Path $DiscoveryOutputPath "AD__Assessment__Report__$timestamp.html"
    }

    # Read assessment summary (look in root and 00_schemas folder)
    $summaryFile = Get-ChildItem -Path $DiscoveryOutputPath -Filter "*Assessment__Summary*" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $summaryFile) {
        $schemasDir = Join-Path $DiscoveryOutputPath '00_schemas'
        if (Test-Path -LiteralPath $schemasDir) {
            $summaryFile = Get-ChildItem -Path $schemasDir -Filter "*Assessment__Summary*" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        }
    }

    $summary = $null
    if ($summaryFile) {
        $summaryData = Import-Csv $summaryFile.FullName
        if ($summaryData -is [array]) { $summary = $summaryData[0] } else { $summary = $summaryData }
    } else {
        # Fallback: build summary from domain data
        $summary = [pscustomobject]@{
            ForestName                   = 'Unknown'
            ForestRootDomain             = 'Unknown'
            DomainsCount                 = 0
            UsersTotal                   = 0
            GroupsTotal                  = 0
            ComputersTotal               = 0
            RunTimestamp                 = (Get-Date).ToString('yyyyMMdd-HHmmss')
            UsersStalePct                = 0
            UsersStaleCount              = 0
            ComputersStalePct            = 0
            ComputersStaleCount          = 0
            HighDepthGroupsCount         = 0
            HighDepthOUsCount            = 0
            AdminSdHolderImpactCount     = 0
            DisabledUsersCount           = 0
            DisabledComputersCount       = 0
            EmptyGroupsCount             = 0
            DuplicateSpnsCount           = 0
            ObjectsRC4OnlyCount          = 0
            ObjectsRC4OnlyPct            = 0
            PrivilegedAccountsCount      = 0
            FsmoUnavailableCount         = 0
            LowTombstoneLifetimeCount    = 0
            WeakPasswordPoliciesCount    = 0
            UsersSIDHistoryCount         = 0
            UsersSIDHistoryPct           = 0
            UsersNonRoutableUPNCount     = 0
            UsersNonRoutableUPNPct       = 0
            CrossDomainDependenciesCount = 0
            HighCostSiteLinksCount       = 0
            TopServiceTypesCount         = 0
        }
    }

    # Read migration risk flags summary (contains Flag, ObjectClass, Count columns)
    $riskSummaryFile = Get-ChildItem -Path $DiscoveryOutputPath -Filter "*Migration__RiskFlagsSummary*" -File | Select-Object -First 1
    $riskSummary = @()
    if ($riskSummaryFile) {
        $riskSummary = @(Import-Csv $riskSummaryFile.FullName)
    }

    # Read per-domain summaries (support nested structure like 20_domains/Domain-*)
    $domainDirs = @()
    $domainRoots = @(
        $DiscoveryOutputPath,
        (Join-Path $DiscoveryOutputPath '20_domains')
    ) | Where-Object { Test-Path $_ -PathType Container }

    foreach ($root in $domainRoots) {
        $domainDirs += (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Domain-' })
    }
    # de-dup
    $domainDirs = $domainDirs | Sort-Object -Property FullName -Unique
    $domainSummaries = @()
    foreach ($ddir in $domainDirs) {
        $domainName = ($ddir.Name -replace '^Domain-', '')
        $usersFile = Get-ChildItem -Path $ddir.FullName -Filter "*Identity__Users__*.csv" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $groupsFile = Get-ChildItem -Path $ddir.FullName -Filter "*Identity__Groups__*.csv" -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $computersFile = Get-ChildItem -Path $ddir.FullName -Filter "*Identity__ComputersAll__*.csv" -File -ErrorAction SilentlyContinue | Select-Object -First 1

        $users = @(); $groups = @(); $computers = @()
        if ($usersFile) { $users = @(Import-Csv $usersFile.FullName) }
        if ($groupsFile) { $groups = @(Import-Csv $groupsFile.FullName) }
        if ($computersFile) { $computers = @(Import-Csv $computersFile.FullName) }

        $usersTotal = @($users).Count
        $groupsTotal = @($groups).Count
        $computersTotal = @($computers).Count

        $usersStale = @($users | Where-Object { ($_.'LastLogonDays' -as [double]) -gt 180 }).Count
        $computersStale = @($computers | Where-Object { ($_.'LastLogonDays' -as [double]) -gt 90 }).Count

        $usersStalePct = if ($usersTotal -gt 0) { [math]::Round(($usersStale / $usersTotal) * 100, 1) } else { 0 }
        $computersStalePct = if ($computersTotal -gt 0) { [math]::Round(($computersStale / $computersTotal) * 100, 1) } else { 0 }

        $summaryObj = [pscustomobject]@{
            UsersTotal        = $usersTotal
            GroupsTotal       = $groupsTotal
            ComputersTotal    = $computersTotal
            UsersStalePct     = $usersStalePct
            ComputersStalePct = $computersStalePct
        }

        $domainSummaries += [pscustomobject]@{
            Domain  = $domainName
            Summary = $summaryObj
        }
    }

    # Parse risk categories from summary data (Flag, ObjectClass, Count)
    # High-risk flags: PasswordAgeOver365d, StaleLastLogonOver180d, Kerberos_NoAES, UPN_NonRoutableSuffix
    $riskCounts = @{
        Critical = 0
        High     = 0
        Medium   = 0
        Low      = 0
    }

    foreach ($item in $riskSummary) {
        # Handle missing or null Count property
        $count = if ($null -ne $item.Count) { [int]$item.Count } else { 0 }
        $flagName = $item.Flag

        # Determine severity based on flag type
        if ($flagName -match 'PasswordAgeOver365d|StaleLastLogonOver180d|Kerberos_NoAES') {
            $riskCounts.High += $count
        } elseif ($flagName -match 'UPN_NonRoutableSuffix|UPN_SuffixNotInForestList') {
            $riskCounts.Medium += $count
        } else {
            $riskCounts.Low += $count
        }
    }

    # Calculate overall health score
    $healthScore = 100
    $healthScore -= ($riskCounts.Critical * 25)  # Each critical = -25
    $healthScore -= ($riskCounts.High * 10)      # Each high = -10
    $healthScore -= ($riskCounts.Medium * 3)     # Each medium = -3
    $healthScore = [math]::Max(0, $healthScore)

    # Determine health status
    $healthStatus = if ($healthScore -ge 80) { 'Healthy' }
    elseif ($healthScore -ge 60) { 'Caution' }
    elseif ($healthScore -ge 40) { 'At Risk' }
    else { 'Critical' }

    # Build HTML
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AD Assessment Report - $($summary.ForestName)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 20px;
            margin-bottom: 30px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        header h1 { font-size: 28px; margin-bottom: 5px; }
        header p { font-size: 14px; opacity: 0.9; }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }
        .metric-card h3 { color: #667eea; font-size: 12px; text-transform: uppercase; margin-bottom: 10px; }
        .metric-card .value { font-size: 32px; font-weight: bold; color: #333; }
        .metric-card .label { font-size: 12px; color: #666; margin-top: 5px; }

        .health-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-left: 4px solid #667eea;
        }
        .health-score {
            font-size: 48px;
            font-weight: bold;
            color: #667eea;
            margin: 10px 0;
        }
        .health-status {
            font-size: 18px;
            font-weight: bold;
            padding: 10px;
            border-radius: 4px;
            display: inline-block;
            margin-top: 10px;
        }
        .health-status.healthy { background: #d4edda; color: #155724; }
        .health-status.caution { background: #fff3cd; color: #856404; }
        .health-status.at-risk { background: #f8d7da; color: #721c24; }
        .health-status.critical { background: #f5c6cb; color: #721c24; }

        .risk-overview {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        .risk-bars {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 15px;
            margin-top: 20px;
        }
        .risk-bar {
            padding: 15px;
            border-radius: 4px;
            text-align: center;
            color: white;
            font-weight: bold;
        }
        .risk-bar.critical { background: #dc3545; }
        .risk-bar.high { background: #fd7e14; }
        .risk-bar.medium { background: #ffc107; color: #333; }
        .risk-bar.low { background: #28a745; }
        .risk-bar .count { font-size: 24px; display: block; margin-bottom: 5px; }

        .section {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .section h2 {
            color: #667eea;
            font-size: 18px;
            margin-bottom: 15px;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        table th {
            background: #f8f9fa;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #667eea;
            font-size: 12px;
            color: #667eea;
        }
        table td {
            padding: 12px;
            border-bottom: 1px solid #e9ecef;
        }
        table tr:hover { background: #f8f9fa; }

        .finding {
            padding: 12px;
            margin: 10px 0;
            border-left: 4px solid #667eea;
            background: #f0f4ff;
        }
        .finding.critical { border-left-color: #dc3545; background: #fff5f5; }
        .finding.high { border-left-color: #fd7e14; background: #fff8f0; }
        .finding.medium { border-left-color: #ffc107; background: #fffbf0; }

        .recommendation {
            padding: 12px;
            margin: 10px 0;
            background: #e8f4f8;
            border-left: 4px solid #17a2b8;
            border-radius: 4px;
        }

        footer {
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 12px;
            margin-top: 40px;
            border-top: 1px solid #e9ecef;
        }

        .footer-text { opacity: 0.7; }
        .report-meta {
            background: #f8f9fa;
            padding: 10px;
            border-radius: 4px;
            font-size: 12px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>Active Directory Assessment Report</h1>
            <p>Forest: $($summary.ForestName) | Root Domain: $($summary.ForestRootDomain) | Generated: $(Get-Date -Format 'MMMM d, yyyy h:mm tt')</p>
        </header>

        <div class="report-meta">
            <strong>Report Metadata:</strong>
            Domains Assessed: $($summary.DomainsCount) |
            Report ID: $(New-Guid) |
            Scope: Forest-wide automated assessment
        </div>

        <!-- Health Score Card -->
        <div class="metrics-grid" style="grid-template-columns: 1fr;">
            <div class="health-card">
                <h3>Forest Health Score</h3>
                <div class="health-score">$healthScore/100</div>
                <div class="health-status $($healthStatus.ToLower())">$healthStatus</div>
            </div>
        </div>

        <!-- Key Metrics -->
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>Identity Objects</h3>
                <div class="value">$([int]$summary.UsersTotal)</div>
                <div class="label">Total Users</div>
            </div>
            <div class="metric-card">
                <h3>Groups</h3>
                <div class="value">$([int]$summary.GroupsTotal)</div>
                <div class="label">Total Groups</div>
            </div>
            <div class="metric-card">
                <h3>Computers</h3>
                <div class="value">$([int]$summary.ComputersTotal)</div>
                <div class="label">Total Computers</div>
            </div>
            <div class="metric-card">
                <h3>Privileged Accounts</h3>
                <div class="value">$([int]$summary.PrivilegedAccountsCount)</div>
                <div class="label">High-risk identities</div>
            </div>
        </div>

        <!-- Risk Overview -->
        <div class="risk-overview">
            <h2>Risk Overview</h2>
            <div class="risk-bars">
                <div class="risk-bar critical">
                    <span class="count">$($riskCounts.Critical)</span>
                    Critical
                </div>
                <div class="risk-bar high">
                    <span class="count">$($riskCounts.High)</span>
                    High
                </div>
                <div class="risk-bar medium">
                    <span class="count">$($riskCounts.Medium)</span>
                    Medium
                </div>
                <div class="risk-bar low">
                    <span class="count">$($riskCounts.Low)</span>
                    Low
                </div>
            </div>
        </div>

        <!-- Key Findings -->
        <div class="section">
            <h2>Key Security Findings</h2>
"@

    # Add findings based on metrics
    $findings = @()

    if ([int]$summary.UsersStaleCount -gt 0) {
        $findings += @{
            Level       = if ([double]$summary.UsersStalePct -gt 10) { 'high' } else { 'medium' }
            Title       = "Stale User Accounts"
            Description = "$([int]$summary.UsersStaleCount) users ($([double]$summary.UsersStalePct)%) have not logged in for 180+ days"
            Action      = "Review and disable inactive accounts per organizational policies"
        }
    }

    if ([int]$summary.ComputersStaleCount -gt 0) {
        $findings += @{
            Level       = if ([double]$summary.ComputersStalePct -gt 10) { 'high' } else { 'medium' }
            Title       = "Stale Computer Accounts"
            Description = "$([int]$summary.ComputersStaleCount) computers ($([double]$summary.ComputersStalePct)%) have not logged in for 90+ days"
            Action      = "Clean up orphaned computer objects and outdated workstation accounts"
        }
    }

    if ([int]$summary.ObjectsRC4OnlyCount -gt 0) {
        $findings += @{
            Level       = 'high'
            Title       = "RC4-Only Encryption"
            Description = "$([int]$summary.ObjectsRC4OnlyCount) objects ($([double]$summary.ObjectsRC4OnlyPct)%) support RC4 encryption only"
            Action      = "Update encryption types to AES128-CTS-HMAC-SHA1-96 or stronger"
        }
    }

    if ([int]$summary.WeakPasswordPoliciesCount -gt 0) {
        $findings += @{
            Level       = 'high'
            Title       = "Weak Password Policies"
            Description = "$([int]$summary.WeakPasswordPoliciesCount) policies detected with insufficient complexity or expiration requirements"
            Action      = "Implement stronger password policies (14+ character, 60-90 day expiration)"
        }
    }

    if ([int]$summary.UsersSIDHistoryCount -gt 0) {
        $findings += @{
            Level       = 'medium'
            Title       = "SID History Present"
            Description = "$([int]$summary.UsersSIDHistoryCount) users ($([double]$summary.UsersSIDHistoryPct)%) have SID history attributes"
            Action      = "Review for migration artifacts; clean up after migration windows close"
        }
    }

    if ([int]$summary.AdminSdHolderImpactCount -gt 0) {
        $findings += @{
            Level       = 'high'
            Title       = "AdminSDHolder Protected Accounts"
            Description = "$([int]$summary.AdminSdHolderImpactCount) accounts have adminCount=1 and are protected by AdminSDHolder"
            Action      = "Regularly audit privileged account permissions; remove unnecessary protections"
        }
    }

    # Add findings from risk summary data (Flag, Count columns)
    if (@($riskSummary).Count -gt 0) {
        $staleCount = ($riskSummary | Where-Object { $_.Flag -eq 'StaleLastLogonOver180d' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($staleCount -gt 0) {
            $findings += @{
                Level       = 'high'
                Title       = "Accounts with Stale Logon Activity"
                Description = "$staleCount accounts have not logged on in 180+ days"
                Action      = "Audit and potentially disable inactive accounts"
            }
        }

        $pwAgeCount = ($riskSummary | Where-Object { $_.Flag -eq 'PasswordAgeOver365d' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($pwAgeCount -gt 0) {
            $findings += @{
                Level       = 'high'
                Title       = "Accounts with Expired Password Age"
                Description = "$pwAgeCount accounts have not changed password in 365+ days"
                Action      = "Force password reset for affected accounts"
            }
        }

        $aesCount = ($riskSummary | Where-Object { $_.Flag -eq 'Kerberos_NoAES' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($aesCount -gt 0) {
            $findings += @{
                Level       = 'high'
                Title       = "Weak Kerberos Encryption"
                Description = "$aesCount accounts do not support AES encryption"
                Action      = "Update encryption types to AES128-CTS-HMAC-SHA1-96 minimum"
            }
        }

        $upnCount = ($riskSummary | Where-Object { $_.Flag -match 'UPN_NonRoutableSuffix|UPN_SuffixNotInForestList' } | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($upnCount -gt 0) {
            $findings += @{
                Level       = 'medium'
                Title       = "Non-Routable UPN Suffixes"
                Description = "$upnCount accounts use non-routable UPN suffixes"
                Action      = "Review and update UPN suffixes to match organizational domain names"
            }
        }

        $disabledCount = ($riskSummary | Where-Object { $_.Flag -eq 'Disabled' } | Select-Object -ExpandProperty Count | Measure-Object -Sum | Select-Object -ExpandProperty Sum) -as [int]
        if ($disabledCount -gt 0) {
            $findings += @{
                Level       = 'low'
                Title       = "Disabled Account Migration Flags"
                Description = "$disabledCount disabled accounts have other risk indicators"
                Action      = "Review for cleanup if objects are no longer needed"
            }
        }
    }

    foreach ($finding in $findings) {
        $html += "            <div class='finding $($finding.Level)'>"
        $html += "                <strong>$($finding.Title)</strong><br/>"
        $html += "                $($finding.Description)<br/>"
        $html += "                <em style='color: #666;'>Action: $($finding.Action)</em>"
        $html += "            </div>"
    }

    $html += @"
        </div>

        <!-- Per-Domain Breakdown -->
        <div class="section">
            <h2>Per-Domain Breakdown</h2>
            <table>
                <thead>
                    <tr>
                        <th>Domain</th>
                        <th>Users</th>
                        <th>Groups</th>
                        <th>Computers</th>
                        <th>Stale Users %</th>
                        <th>Stale Computers %</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($ds in $domainSummaries) {
        $s = $ds.Summary
        $html += "                    <tr>"
        $html += "                        <td>$($ds.Domain)</td>"
        $html += "                        <td>$([int]$s.UsersTotal)</td>"
        $html += "                        <td>$([int]$s.GroupsTotal)</td>"
        $html += "                        <td>$([int]$s.ComputersTotal)</td>"
        $html += "                        <td>$([double]$s.UsersStalePct)%</td>"
        $html += "                        <td>$([double]$s.ComputersStalePct)%</td>"
        $html += "                    </tr>"
    }

    $html += @"
                </tbody>
            </table>
        </div>

        <!-- Recommendations -->
        <div class="section">
            <h2>Remediation Roadmap</h2>
"@

    $recommendations = @(
        "1. <strong>Immediate (0-30 days):</strong> Disable stale user and computer accounts; address weak password policies",
        "2. <strong>Short-term (1-3 months):</strong> Update encryption settings to AES; audit and clean SID history",
        "3. <strong>Medium-term (3-6 months):</strong> Review AdminSDHolder protected accounts; implement stronger access controls",
        "4. <strong>Ongoing:</strong> Monitor for new stale accounts; enforce organizational security policies"
    )

    foreach ($rec in $recommendations) {
        $html += "            <div class='recommendation'>$rec</div>"
    }

    $html += @"
        </div>

        <footer>
            <p class="footer-text">This report was generated by Paul Lagana Toolkit v0.1.1</p>
            <p class="footer-text">For detailed findings, review individual CSV reports in the discovery output folder</p>
        </footer>
    </div>
</body>
</html>
"@

    # Write HTML to file
    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

    [pscustomobject]@{
        ReportPath    = $OutputPath
        ForestName    = $summary.ForestName
        HealthScore   = $healthScore
        HealthStatus  = $healthStatus
        TotalFindings = $findings.Count
        CriticalRisks = $riskCounts.Critical
        HighRisks     = $riskCounts.High
    }
}
