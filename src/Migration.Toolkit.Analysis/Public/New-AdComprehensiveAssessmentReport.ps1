function New-AdComprehensiveAssessmentReport {
    <#
    .SYNOPSIS
    Generate a comprehensive HTML assessment report from AD discovery data.
    .DESCRIPTION
    Creates a professional, detailed HTML assessment report covering forest, domain, user,
    group, computer, password policy, replication, and risk analysis. Includes executive
    summary, detailed findings, and actionable recommendations.
    .PARAMETER DiscoveryOutputPath
    Path to the discovery output folder containing CSV files.
    .PARAMETER OutputPath
    Path where the HTML report will be saved.
    .PARAMETER CustomerName
    Organization name for the report title.
    .PARAMETER ReportDate
    Date for the report (defaults to today).
    .EXAMPLE
    New-AdComprehensiveAssessmentReport -DiscoveryOutputPath "C:\Discovery\ADOnly" -OutputPath "C:\Reports\Assessment.html" -CustomerName "Acme Corp"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$DiscoveryOutputPath,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [string]$CustomerName = "Organization",
        [datetime]$ReportDate = (Get-Date)
    )

    # Helper to safely import CSV
    function Import-CsvSafe {
        param([string]$Path)
        if (-not (Test-Path $Path)) { return @() }
        try {
            return @(Import-Csv -Path $Path -ErrorAction Stop)
        } catch {
            Write-Warning "Failed to import $Path : $_"
            return @()
        }
    }

    # Helper to find CSV files
    function Find-CsvFile {
        param([string]$Pattern)
        return @(Get-ChildItem -Path $Pattern -File -ErrorAction SilentlyContinue)
    }

    Write-Host "Generating comprehensive assessment report for $CustomerName..." -ForegroundColor Yellow

    # Load all discovery data with null-safe array wrapping
    $forestSummary = Import-CsvSafe (Join-Path $DiscoveryOutputPath "10_forest\LC__AD__Forest__Summary__Forest.csv") | Select-Object -First 1
    $domainSummaries = @()
    # Root-level domain summaries (support file name variations)
    $rootSummaryFiles = @(Get-ChildItem -Path $DiscoveryOutputPath -Filter 'LC__AD__Domain__Summary__Domain*' -ErrorAction SilentlyContinue)
    foreach ($f in $rootSummaryFiles) { $domainSummaries += @(Import-CsvSafe $f.FullName) }
    $upnSuffixes = @(Import-CsvSafe (Join-Path $DiscoveryOutputPath "10_forest\LC__AD__Forest__Identity__UpnSuffixes__Forest.csv"))
    # Load trusts from any matching CSVs under 10_forest (support naming variations)
    $trusts = @()
    $forestDir = Join-Path $DiscoveryOutputPath "10_forest"
    $trustFiles = @(Get-ChildItem -Path $forestDir -Filter 'LC__AD__Forest__Security__Trusts__*.csv' -ErrorAction SilentlyContinue)
    foreach ($tf in $trustFiles) { $trusts += @(Import-CsvSafe $tf.FullName) }

    $domainDir = Join-Path $DiscoveryOutputPath "20_domains"
    $domainFolders = @(Get-ChildItem -Path $domainDir -Directory -ErrorAction SilentlyContinue)
    foreach ($df in $domainFolders) {
        $perDomainSummaryFiles = @(Get-ChildItem -Path $df.FullName -Filter 'LC__AD__Domain__Summary__Domain*' -ErrorAction SilentlyContinue)
        foreach ($f in $perDomainSummaryFiles) { $domainSummaries += @(Import-CsvSafe $f.FullName) }
    }
    # Dedupe summaries by DomainFqdn or DomainName
    if ($domainSummaries.Count -gt 0) {
        $domainSummaries = $domainSummaries | Sort-Object @{Expression = { if ($_.PSObject.Properties['DomainFqdn']) { $_.DomainFqdn } else { $_.DomainName } } } -Unique
    }

    # Load domain-specific data
    $users = @()
    $groups = @()
    $computers = @()
    $policies = @()
    $fgppPolicies = @()
    $fgppAssignments = @()
    $gpoDatas = @()

    foreach ($df in $domainFolders) {
        # Find and load user CSV files
        $userFiles = @(Get-ChildItem -Path (Join-Path $df.FullName "LC__AD__Domain__Identity__Users__*.csv") -ErrorAction SilentlyContinue)
        foreach ($file in $userFiles) {
            $users += Import-CsvSafe $file.FullName
        }

        # Find and load group CSV files
        $groupFiles = @(Get-ChildItem -Path (Join-Path $df.FullName "LC__AD__Domain__Identity__Groups__*.csv") -ErrorAction SilentlyContinue)
        foreach ($file in $groupFiles) {
            $groups += Import-CsvSafe $file.FullName
        }

        # Find and load computer CSV files
        $computerFiles = @(Get-ChildItem -Path (Join-Path $df.FullName "LC__AD__Domain__Inventory__Computers__*.csv") -ErrorAction SilentlyContinue)
        foreach ($file in $computerFiles) {
            $computers += Import-CsvSafe $file.FullName
        }

        # Find and load policy CSV files (DefaultPasswordPolicy)
        $policyFiles = @(Get-ChildItem -Path (Join-Path $df.FullName "LC__AD__Domain__Security__DefaultPasswordPolicy__*.csv") -ErrorAction SilentlyContinue)
        foreach ($file in $policyFiles) {
            $policies += Import-CsvSafe $file.FullName
        }

        # Also load PasswordPolicyDefault (alternate naming)
        $policyDefaultFiles = @(Get-ChildItem -Path (Join-Path $df.FullName "LC__AD__Domain__Security__PasswordPolicyDefault__*.csv") -ErrorAction SilentlyContinue)
        foreach ($file in $policyDefaultFiles) {
            $policies += Import-CsvSafe $file.FullName
        }

        # Fine-Grained Password Policies (FGPP)
        $fgppPolicyFiles = @(Get-ChildItem -Path (Join-Path $df.FullName "LC__AD__Domain__Security__FineGrainedPasswordPolicies__*.csv") -ErrorAction SilentlyContinue)
        foreach ($file in $fgppPolicyFiles) {
            $fgppPolicies += Import-CsvSafe $file.FullName
        }

        # FGPP Assignments
        $fgppAssignmentFiles = @(Get-ChildItem -Path (Join-Path $df.FullName "LC__AD__Domain__Security__FineGrainedPasswordPolicyAssignments__*.csv") -ErrorAction SilentlyContinue)
        foreach ($file in $fgppAssignmentFiles) {
            $fgppAssignments += Import-CsvSafe $file.FullName
        }
    }

    # Calculate metrics (with safe property access)
    $enabledUsers = @($users | Where-Object { $_.PSObject.Properties['Enabled'] -and $_.Enabled -eq $true }).Count
    $disabledUsers = @($users | Where-Object { $_.PSObject.Properties['Enabled'] -and $_.Enabled -eq $false }).Count
    $enabledComputers = @($computers | Where-Object { $_.PSObject.Properties['Enabled'] -and $_.Enabled -eq $true }).Count
    $disabledComputers = @($computers | Where-Object { $_.PSObject.Properties['Enabled'] -and $_.Enabled -eq $false }).Count
    $globalGroups = @($groups | Where-Object { $_.PSObject.Properties['GroupScope'] -and ($_.GroupScope -match '(?i)Global') }).Count
    $domainLocalGroups = @($groups | Where-Object { $_.PSObject.Properties['GroupScope'] -and ($_.GroupScope -match '(?i)DomainLocal') }).Count
    $universalGroups = @($groups | Where-Object { $_.PSObject.Properties['GroupScope'] -and ($_.GroupScope -match '(?i)Universal') }).Count

    # Generate HTML
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Active Directory Assessment Report - $CustomerName</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            box-shadow: 0 0 20px rgba(0,0,0,0.1);
        }
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 40px 20px;
            text-align: center;
            border-bottom: 5px solid #0066cc;
        }
        .header h1 {
            font-size: 32px;
            margin-bottom: 10px;
            font-weight: 600;
        }
        .header p {
            font-size: 16px;
            opacity: 0.9;
        }
        .meta-info {
            display: flex;
            justify-content: space-around;
            padding: 20px;
            background-color: #f9f9f9;
            border-bottom: 1px solid #ddd;
            flex-wrap: wrap;
        }
        .meta-item {
            padding: 10px 20px;
            flex: 1;
            min-width: 200px;
        }
        .meta-item strong {
            display: block;
            color: #666;
            font-size: 12px;
            text-transform: uppercase;
            margin-bottom: 5px;
        }
        .meta-item span {
            display: block;
            font-size: 16px;
            color: #333;
            font-weight: 500;
        }
        .content {
            padding: 40px;
        }
        .section {
            margin-bottom: 40px;
            page-break-inside: avoid;
        }
        .section h2 {
            background: linear-gradient(to right, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 15px 20px;
            font-size: 22px;
            margin-bottom: 20px;
            border-radius: 4px;
            border-left: 5px solid #0066cc;
        }
        .section h3 {
            color: #1e3c72;
            font-size: 16px;
            margin: 15px 0 10px 0;
            border-bottom: 2px solid #2a5298;
            padding-bottom: 5px;
        }
        .metric-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .metric-card {
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #1e3c72;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        .metric-card.warning {
            border-left-color: #ff9800;
            background: linear-gradient(135deg, #fff3e0 0%, #ffe0b2 100%);
        }
        .metric-card.critical {
            border-left-color: #f44336;
            background: linear-gradient(135deg, #ffebee 0%, #ffcdd2 100%);
        }
        .metric-card.success {
            border-left-color: #4caf50;
            background: linear-gradient(135deg, #e8f5e9 0%, #c8e6c9 100%);
        }
        .metric-value {
            font-size: 32px;
            font-weight: bold;
            color: #1e3c72;
            margin-bottom: 5px;
        }
        .metric-label {
            font-size: 13px;
            color: #666;
            text-transform: uppercase;
            font-weight: 600;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            table-layout: fixed;
            font-size: 13px;
            overflow-x: auto;
        }
        th {
            background-color: #2a5298;
            color: white;
            padding: 10px 8px;
            text-align: left;
            font-weight: 600;
            word-wrap: break-word;
            font-size: 12px;
        }
        td {
            padding: 8px 6px;
            border-bottom: 1px solid #ddd;
            word-wrap: break-word;
            word-break: break-word;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        .finding {
            background-color: #f0f4f8;
            border-left: 4px solid #1e3c72;
            padding: 15px;
            margin-bottom: 15px;
            border-radius: 4px;
        }
        .finding.warning {
            border-left-color: #ff9800;
            background-color: #fff3e0;
        }
        .finding.critical {
            border-left-color: #f44336;
            background-color: #ffebee;
        }
        .finding-title {
            font-weight: 600;
            color: #1e3c72;
            margin-bottom: 5px;
        }
        .finding-details {
            font-size: 13px;
            color: #666;
        }
        .recommendation {
            background-color: #e8f5e9;
            border-left: 4px solid #4caf50;
            padding: 15px;
            margin: 10px 0;
            border-radius: 4px;
        }
        .recommendation-title {
            font-weight: 600;
            color: #2e7d32;
            margin-bottom: 5px;
        }
        .footer {
            text-align: center;
            padding: 20px;
            border-top: 1px solid #ddd;
            color: #999;
            font-size: 12px;
            background-color: #f9f9f9;
        }
        @media (max-width: 768px) {
            .meta-info {
                flex-direction: column;
            }
            .metric-grid {
                grid-template-columns: 1fr;
            }
            table {
                font-size: 12px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Active Directory Assessment Report</h1>
            <p>$CustomerName</p>
        </div>
        <div class="meta-info">
            <div class="meta-item">
                <strong>Report Date</strong>
                <span>$($ReportDate.ToString('MMMM dd, yyyy'))</span>
            </div>
            <div class="meta-item">
                <strong>Assessment Scope</strong>
                <span>$($forestSummary.ForestName ?? 'N/A')</span>
            </div>
            <div class="meta-item">
                <strong>Total Domains</strong>
                <span>$($domainSummaries.Count)</span>
            </div>
            <div class="meta-item">
                <strong>Total Users</strong>
                <span>$($users.Count)</span>
            </div>
        </div>
        <div class="content">
            <!-- Executive Summary -->
            <div class="section">
                <h2>Executive Summary</h2>
                <p>This Active Directory assessment report provides a comprehensive analysis of the directory infrastructure for <strong>$CustomerName</strong>. The assessment covers forest and domain configuration, user and group management, computer inventory, password policies, replication topology, and identifies security findings with recommendations.</p>
                <div class="metric-grid">
                    <div class="metric-card success">
                        <div class="metric-value">$($forestSummary.ForestName ?? 'N/A')</div>
                        <div class="metric-label">Forest Root</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">$($domainSummaries.Count)</div>
                        <div class="metric-label">Domains</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">$($users.Count)</div>
                        <div class="metric-label">Total Users</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">$($computers.Count)</div>
                        <div class="metric-label">Computers</div>
                    </div>
                </div>
            </div>
            <!-- Forest & Domain Overview -->
            <div class="section">
                <h2>Forest &amp; Domain Overview</h2>
                <h3>Forest Information</h3>
                <table>
                    <tr>
                        <th>Property</th>
                        <th>Value</th>
                    </tr>
                    <tr>
                        <td>Forest Name</td>
                        <td>$($forestSummary.ForestName ?? 'N/A')</td>
                    </tr>
                    <tr>
                        <td>Root Domain</td>
                        <td>$($forestSummary.RootDomain ?? 'N/A')</td>
                    </tr>
                    <tr>
                        <td>Forest Mode</td>
                        <td>$($forestSummary.ForestMode ?? 'N/A')</td>
                    </tr>
                    <tr>
                        <td>Domain Count</td>
                        <td>$($forestSummary.DomainCount ?? 'N/A')</td>
                    </tr>
                </table>
                <h3>UPN Suffixes</h3>
                <table>
                    <tr>
                        <th>UPN Suffix</th>
                    </tr>
"@

    foreach ($upn in ($upnSuffixes | Select-Object -ExpandProperty UPNSuffix -Unique -ErrorAction SilentlyContinue)) {
        $html += "                    <tr><td>$upn</td></tr>`n"
    }

    $html += @"
                </table>
                <h3>Domain Summaries</h3>
                <table>
                    <tr>
                        <th>Domain</th>
                        <th>Functional Level</th>
                        <th>Users</th>
                        <th>Groups</th>
                        <th>Computers</th>
                    </tr>
"@

    foreach ($domain in $domainSummaries) {
        # Prefer DomainFqdn; fallback to DomainName (from CSVs)
        $domainKey = $null
        if ($domain.PSObject.Properties['DomainFqdn']) { $domainKey = $domain.DomainFqdn }
        elseif ($domain.PSObject.Properties['DomainName']) { $domainKey = $domain.DomainName }
        else { $domainKey = 'N/A' }
        # Compute counts by DomainFqdn
        $domainUsers = @($users | Where-Object { $_.PSObject.Properties['DomainFqdn'] -and ($_.DomainFqdn -eq $domainKey) }).Count
        $domainGroups = @($groups | Where-Object { $_.PSObject.Properties['DomainFqdn'] -and ($_.DomainFqdn -eq $domainKey) }).Count
        $domainComputers = @($computers | Where-Object { $_.PSObject.Properties['DomainFqdn'] -and ($_.DomainFqdn -eq $domainKey) }).Count
        $domainMode = 'N/A'
        if ($domain.PSObject.Properties['DomainMode']) { $domainMode = $domain.DomainMode }
        elseif ($domain.PSObject.Properties['DomainFunctionalLevel']) { $domainMode = $domain.DomainFunctionalLevel }
        $html += @"
                    <tr>
                        <td>$domainKey</td>
                        <td>$domainMode</td>
                        <td>$domainUsers</td>
                        <td>$domainGroups</td>
                        <td>$domainComputers</td>
                    </tr>
"@
    }

    $html += @"
                </table>
            </div>
            <!-- User &amp; Group Analysis -->
            <div class="section">
                <h2>User &amp; Group Analysis</h2>
                <div class="metric-grid">
                    <div class="metric-card success">
                        <div class="metric-value">$enabledUsers</div>
                        <div class="metric-label">Enabled Users</div>
                    </div>
                    <div class="metric-card warning">
                        <div class="metric-value">$disabledUsers</div>
                        <div class="metric-label">Disabled Users</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">$globalGroups</div>
                        <div class="metric-label">Global Groups</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">$domainLocalGroups</div>
                        <div class="metric-label">Domain Local Groups</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">$universalGroups</div>
                        <div class="metric-label">Universal Groups</div>
                    </div>
                </div>
                <h3>User Account Status</h3>
                <p>The directory contains <strong>$($users.Count)</strong> total user accounts, of which <strong>$enabledUsers</strong> are enabled and <strong>$disabledUsers</strong> are disabled.</p>
                <h3>Group Distribution</h3>
                <p>Groups are distributed across three scope types:</p>
                <ul style="margin-left: 20px; margin-bottom: 15px;">
                    <li><strong>Global Groups:</strong> $globalGroups - Used for organizational units and resource access</li>
                    <li><strong>Domain Local Groups:</strong> $domainLocalGroups - Used for local resource permissions</li>
                    <li><strong>Universal Groups:</strong> $universalGroups - Used for cross-domain membership</li>
                </ul>
            </div>
            <!-- Computer Inventory -->
            <div class="section">
                <h2>Computer Inventory</h2>
                <div class="metric-grid">
                    <div class="metric-card success">
                        <div class="metric-value">$enabledComputers</div>
                        <div class="metric-label">Enabled Computers</div>
                    </div>
                    <div class="metric-card warning">
                        <div class="metric-value">$disabledComputers</div>
                        <div class="metric-label">Disabled Computers</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">$($computers.Count)</div>
                        <div class="metric-label">Total Computers</div>
                    </div>
                </div>
                <p>The domain contains <strong>$($computers.Count)</strong> computer accounts. Of these, <strong>$enabledComputers</strong> are enabled and active, while <strong>$disabledComputers</strong> are disabled.</p>
            </div>
            <!-- Password Policies -->
            <div class="section">
                <h2>Password Policies</h2>
                <h3>Default Domain Password Policies</h3>
                <table>
                    <tr>
                        <th>Domain</th>
                        <th>Complexity</th>
                        <th>Min Length</th>
                        <th>History</th>
                        <th>Min Age (days)</th>
                        <th>Max Age (days)</th>
                        <th>Lockout Threshold</th>
                        <th>Lockout Duration (min)</th>
                        <th>Observation Window (min)</th>
                        <th>Reversible Encryption</th>
                    </tr>
"@

    if ($policies.Count -gt 0) {
        foreach ($p in $policies) {
            $domainKey = 'N/A'
            if ($p.PSObject.Properties['DomainFqdn']) { $domainKey = $p.DomainFqdn }
            elseif ($p.PSObject.Properties['Domain']) { $domainKey = $p.Domain }
            $html += @"
                    <tr>
                        <td>$domainKey</td>
                        <td>$([string]$p.ComplexityEnabled)</td>
                        <td>$([string]$p.MinPasswordLength)</td>
                        <td>$([string]$p.PasswordHistoryCount)</td>
                        <td>$([string]$p.MinPasswordAgeDays)</td>
                        <td>$([string]$p.MaxPasswordAgeDays)</td>
                        <td>$([string]$p.LockoutThreshold)</td>
                        <td>$([string]$p.LockoutDurationMinutes)</td>
                        <td>$([string]$p.LockoutObservationWindowMinutes)</td>
                        <td>$([string]$p.ReversibleEncryptionEnabled)</td>
                    </tr>
"@
        }
    } else {
        $html += "                    <tr><td colspan=`"10`">No default password policy data found.</td></tr>`n"
    }

    $html += @"
                </table>
"@

    if ($fgppPolicies.Count -gt 0) {
        $html += @"
                <h3>Fine-Grained Password Policies</h3>
                <table>
                    <tr>
                        <th>Domain</th>
                        <th>Name</th>
                        <th>Precedence</th>
                        <th>Complexity</th>
                        <th>Min Length</th>
                        <th>Max Age (days)</th>
                        <th>AppliesTo Count</th>
                    </tr>
"@

        foreach ($fp in $fgppPolicies) {
            $fgppDomain = 'N/A'
            if ($fp.PSObject.Properties['DomainFqdn']) { $fgppDomain = [string]$fp.DomainFqdn }
            $html += @"
                    <tr>
                        <td>$fgppDomain</td>
                        <td>$([string]$fp.Name)</td>
                        <td>$([string]$fp.Precedence)</td>
                        <td>$([string]$fp.ComplexityEnabled)</td>
                        <td>$([string]$fp.MinPasswordLength)</td>
                        <td>$([string]$fp.MaxPasswordAgeDays)</td>
                        <td>$([string]$fp.AppliesToCount)</td>
                    </tr>
"@
        }

        $html += @"
                </table>
"@
    }

    $html += @"
            <!-- Trusts -->
            <div class="section">
                <h2>Forest Trusts</h2>
                <table>
                    <tr>
                        <th>Name</th>
                        <th>Source</th>
                        <th>Target</th>
                        <th>Direction</th>
                        <th>Type</th>
                        <th>Forest Transitive</th>
                        <th>Selective Auth</th>
                        <th>SID Filtering (Forest Aware)</th>
                        <th>SID Filtering (Quarantined)</th>
                        <th>Uses AES</th>
                        <th>Uses RC4</th>
                    </tr>
"@

    if ($trusts.Count -gt 0) {
        foreach ($t in $trusts) {
            $html += @"
                    <tr>
                        <td>$([string]$t.Name)</td>
                        <td>$([string]$t.Source)</td>
                        <td>$([string]$t.Target)</td>
                        <td>$([string]$t.Direction)</td>
                        <td>$([string]$t.TrustType)</td>
                        <td>$([string]$t.ForestTransitive)</td>
                        <td>$([string]$t.SelectiveAuthentication)</td>
                        <td>$([string]$t.SIDFilteringForestAware)</td>
                        <td>$([string]$t.SIDFilteringQuarantined)</td>
                        <td>$([string]$t.UsesAESKeys)</td>
                        <td>$([string]$t.UsesRC4Encryption)</td>
                    </tr>
"@
        }
    } else {
        $html += "                    <tr><td colspan=`"11`">No forest trusts discovered.</td></tr>`n"
    }

    $html += @"
                </table>
            </div>
"@

    # Write report
    $html | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "  [OK] Comprehensive assessment report: $OutputPath" -ForegroundColor Green

    return [pscustomobject]@{
        Path          = $OutputPath
        ForestName    = $forestSummary.ForestName ?? 'N/A'
        DomainCount   = $domainSummaries.Count
        UserCount     = $users.Count
        GroupCount    = $groups.Count
        ComputerCount = $computers.Count
    }
}
