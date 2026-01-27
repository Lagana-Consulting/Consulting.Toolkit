function New-AdMigrationPlanningReport {
  <#
    .SYNOPSIS
    Generate a migration planning report with complexity drivers, LOE estimates, and SOW outline.

    .PARAMETER DiscoveryOutputPath
    Path to the discovery output folder (root of a run or a compare snapshot).

    .PARAMETER OutputPath
    Optional path for the resulting HTML. Defaults inside DiscoveryOutputPath.

    .NOTES
    Reads forest-level and domain-level CSVs. Handles missing data gracefully.
    #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$DiscoveryOutputPath,
    [string]$OutputPath
  )

  if (-not $OutputPath) {
    $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $OutputPath = Join-Path $DiscoveryOutputPath "LC__Migration__Planning__Report__$ts.html"
  }

  # Helper: safe import
  function _imp($p) { if (Test-Path $p) { try { @(Import-Csv $p) } catch { @() } } else { @() } }

  # Root + nested paths
  $forestPath = $DiscoveryOutputPath
  $forest10 = Join-Path $DiscoveryOutputPath '10_forest'
  $domains20 = Join-Path $DiscoveryOutputPath '20_domains'

  # Forest summary
  $forestSummaryFile = Get-ChildItem -Path $forestPath -Filter '*Assessment__Summary*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $forestSummaryFile) {
    $forestSummaryFile = Get-ChildItem -Path $forest10 -Filter '*Forest__Summary*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  }
  $forestSummary = @()
  if ($forestSummaryFile) { $forestSummary = @(Import-Csv $forestSummaryFile.FullName) }
  $summaryRow = if ($forestSummary.Count -gt 0) { $forestSummary[0] } else { $null }

  # Migration risk summary
  $riskFile = Get-ChildItem -Path $forestPath -Filter '*Migration__RiskFlagsSummary*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  $riskSummary = if ($riskFile) { _imp($riskFile.FullName) } else { @() }

  # Forest analyses
  $siteLinkFile = Get-ChildItem -Path $forest10 -Filter '*SiteLinkCostAnalysis*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  $siteLinkCost = if ($siteLinkFile) { _imp($siteLinkFile.FullName) } else { @() }
  $fsmoFile = Get-ChildItem -Path $forest10 -Filter '*FsmoRoleAvailability*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  $fsmoAvail = if ($fsmoFile) { _imp($fsmoFile.FullName) } else { @() }
  $trustFile = Get-ChildItem -Path $forest10 -Filter '*TrustRelationshipMap*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  $trustMap = if ($trustFile) { _imp($trustFile.FullName) } else { @() }
  $certFile = Get-ChildItem -Path $forest10 -Filter '*CertificateServicesInventory*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  $certSvc = if ($certFile) { _imp($certFile.FullName) } else { @() }
  $admtFile = Get-ChildItem -Path $forest10 -Filter '*DuplicateObjectsForAdmt*Forest*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
  $admtDup = if ($admtFile) { _imp($admtFile.FullName) } else { @() }

  # Domain folders
  $domainDirs = @()
  foreach ($root in @($DiscoveryOutputPath, $domains20)) {
    if (Test-Path $root) {
      $domainDirs += (Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Domain-' })
    }
  }
  $domainDirs = $domainDirs | Sort-Object -Property FullName -Unique

  # Aggregate identity
  $usersTotal = 0; $groupsTotal = 0; $computersTotal = 0
  $usersStale = 0; $computersStale = 0
  foreach ($ddir in $domainDirs) {
    $usersFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__Users__*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $groupsFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__Groups__*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $computersFile = Get-ChildItem -Path $ddir.FullName -Filter '*Identity__ComputersAll__*.csv' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $users = if ($usersFile) { @(Import-Csv $usersFile.FullName) } else { @() }
    $groups = if ($groupsFile) { @(Import-Csv $groupsFile.FullName) } else { @() }
    $computers = if ($computersFile) { @(Import-Csv $computersFile.FullName) } else { @() }
    $usersTotal += @($users).Count
    $groupsTotal += @($groups).Count
    $computersTotal += @($computers).Count
    $usersStale += @($users | Where-Object { ($_.'LastLogonDays' -as [double]) -gt 180 }).Count
    $computersStale += @($computers | Where-Object { ($_.'LastLogonDays' -as [double]) -gt 90 }).Count
  }

  # Other domain-level analyses to drive complexity
  $groupNesting = @()
  $ouDepth = @()
  $crossDomain = @()
  $emptyGroups = @()
  $dupSpns = @()
  $disabled = @()
  $adminSd = @()
  $tokenBloat = @()
  $gpoInventory = @()

  foreach ($ddir in $domainDirs) {
    $f1 = Get-ChildItem $ddir.FullName -Filter '*GroupNestingDepth*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $groupNesting += if ($f1) { _imp($f1.FullName) } else { @() }
    $f2 = Get-ChildItem $ddir.FullName -Filter '*OuDepthAnalysis*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $ouDepth += if ($f2) { _imp($f2.FullName) } else { @() }
    $f3 = Get-ChildItem $ddir.FullName -Filter '*CrossDomainGroupMembership*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $crossDomain += if ($f3) { _imp($f3.FullName) } else { @() }
    $f4 = Get-ChildItem $ddir.FullName -Filter '*EmptyGroups*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $emptyGroups += if ($f4) { _imp($f4.FullName) } else { @() }
    $f5 = Get-ChildItem $ddir.FullName -Filter '*DuplicateSpns*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $dupSpns += if ($f5) { _imp($f5.FullName) } else { @() }
    $f6 = Get-ChildItem $ddir.FullName -Filter '*DisabledAccounts*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $disabled += if ($f6) { _imp($f6.FullName) } else { @() }
    $f7 = Get-ChildItem $ddir.FullName -Filter '*AdminSdHolderImpact*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $adminSd += if ($f7) { _imp($f7.FullName) } else { @() }
    $f8 = Get-ChildItem $ddir.FullName -Filter '*GroupTokenBloat*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $tokenBloat += if ($f8) { _imp($f8.FullName) } else { @() }
    $gpoInventory += _imp((Get-ChildItem $ddir.FullName -Filter '*GPO__Inventory*' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName)
  }

  # Complexity score (0-100): weighted drivers
  $score = 0
  $groupNestingDeep = @($groupNesting | Where-Object { $_.PSObject.Properties['NestingDepth'] -and ($_.'NestingDepth' -as [int]) -ge 3 })
  $ouDepthMax = @($ouDepth | ForEach-Object { if ($_.PSObject.Properties['MaxDepth']) { $_.'MaxDepth' -as [int] } } | Where-Object { $_ -ge 6 })
  $crossDomainCount = @($crossDomain).Count
  $dupSpnsCount = @($dupSpns).Count
  $emptyGroupsCount = @($emptyGroups).Count
  $adminSdCount = @($adminSd).Count
  $tokenBloatCount = @($tokenBloat).Count
  $disabledCount = @($disabled).Count
  $trustMapCount = @($trustMap).Count

  $score += [math]::Min(30, [math]::Round(($usersTotal / 1000.0) * 5))       # identity volume
  $score += [math]::Min(15, $groupNestingDeep.Count)
  $score += [math]::Min(10, $ouDepthMax.Count)
  $score += [math]::Min(10, $crossDomainCount)                      # cross-domain dependencies
  $score += [math]::Min(10, $dupSpnsCount)
  $score += [math]::Min(10, $emptyGroupsCount)
  $score += [math]::Min(10, $adminSdCount)
  $score += [math]::Min(10, $tokenBloatCount)
  $score += [math]::Min(10, $disabledCount)
  $score += [math]::Min(10, $trustMapCount)
  $score = [math]::Min(100, $score)

  # LOE estimation (days) by phase
  $usersWaves = [math]::Ceiling(($usersTotal) / 500.0)
  $computersWaves = [math]::Ceiling(($computersTotal) / 250.0)
  $depFactor = [math]::Min(5, @($crossDomain).Count / 5.0)

  $loeAssessment = [math]::Max(2, [math]::Ceiling(@($domainDirs).Count * 0.5))
  $loeRemediation = [math]::Ceiling((@($dupSpns).Count + @($emptyGroups).Count + @($adminSd).Count + @($tokenBloat).Count + @($disabled).Count) / 50.0) + [math]::Ceiling(($usersStale + $computersStale) / 200.0)
  $loeExecution = [math]::Ceiling(($usersWaves * 2) + ($computersWaves * 2) + $depFactor)
  $loePost = 2
  $loeTotal = $loeAssessment + $loeRemediation + $loeExecution + $loePost

  # Build HTML
  $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AD Migration Planning - $($summaryRow.ForestName)</title>
<style>
body{font-family:'Segoe UI',Tahoma,Arial,sans-serif;background:#f5f5f5;color:#333;}
.container{max-width:1200px;margin:0 auto;padding:24px;}
.card{background:#fff;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,.1);padding:20px;margin-bottom:16px;}
.hdr{background:linear-gradient(135deg,#667eea,#764ba2);color:#fff;border-radius:8px;padding:28px;margin-bottom:16px;}
.hdr h1{margin:0;font-size:24px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px}
.kpi{background:#fff;border-left:4px solid #667eea;border-radius:8px;padding:16px}
.kpi .label{font-size:12px;color:#666}
.kpi .val{font-size:28px;font-weight:bold}
.table{width:100%;border-collapse:collapse}
.table th{background:#f8f9fa;color:#667eea;font-size:12px;border-bottom:2px solid #667eea;padding:8px;text-align:left}
.table td{border-bottom:1px solid #eee;padding:8px}
.badge{display:inline-block;padding:4px 8px;border-radius:12px;font-size:12px;margin-right:6px}
.badge.ok{background:#d4edda;color:#155724}
.badge.warn{background:#fff3cd;color:#856404}
.badge.risk{background:#f8d7da;color:#721c24}
</style>
</head>
<body>
<div class="container">
<div class="hdr"><h1>Active Directory Migration Planning</h1><div>Forest: $($summaryRow.ForestName) | Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div></div>

<div class="grid">
  <div class="kpi"><div class="label">Users</div><div class="val">$usersTotal</div></div>
  <div class="kpi"><div class="label">Groups</div><div class="val">$groupsTotal</div></div>
  <div class="kpi"><div class="label">Computers</div><div class="val">$computersTotal</div></div>
  <div class="kpi"><div class="label">Complexity Score</div><div class="val">$score/100</div></div>
</div>

<div class="card">
  <h3>Complexity Drivers</h3>
  <table class="table">
    <tr><th>Driver</th><th>Indicator</th><th>Notes</th></tr>
    <tr><td>Group Nesting</td><td>$($groupNestingDeep.Count)</td><td>Groups with nesting depth ≥ 3</td></tr>
    <tr><td>OU Depth</td><td>$($ouDepthMax.Count)</td><td>Domains with OU depth ≥ 6</td></tr>
    <tr><td>Cross-Domain Membership</td><td>$crossDomainCount</td><td>Groups with cross-domain members</td></tr>
    <tr><td>Duplicate SPNs</td><td>$dupSpnsCount</td><td>Duplicate SPN entries detected</td></tr>
    <tr><td>Empty Groups</td><td>$emptyGroupsCount</td><td>Groups with zero members</td></tr>
    <tr><td>AdminSDHolder Impact</td><td>$adminSdCount</td><td>Protected accounts/groups</td></tr>
    <tr><td>Token Bloat</td><td>$tokenBloatCount</td><td>High token size candidates</td></tr>
    <tr><td>Disabled Accounts</td><td>$disabledCount</td><td>Disabled users/computers</td></tr>
    <tr><td>Trusts</td><td>$trustMapCount</td><td>Forest/domain trusts present</td></tr>
  </table>
</div>

<div class="card">
  <h3>Level of Effort (LOE)</h3>
  <table class="table">
    <tr><th>Phase</th><th>Estimate (days)</th><th>Notes</th></tr>
    <tr><td>Assessment & Planning</td><td>$loeAssessment</td><td>Discovery review, wave design</td></tr>
    <tr><td>Remediation</td><td>$loeRemediation</td><td>SPN cleanup, empty groups, AdminSDHolder, disabled accounts</td></tr>
    <tr><td>Migration Execution</td><td>$loeExecution</td><td>$usersWaves user waves | $computersWaves computer waves</td></tr>
    <tr><td>Post-Migration</td><td>$loePost</td><td>Validation, decommission, final reporting</td></tr>
    <tr><td><strong>Total</strong></td><td><strong>$loeTotal</strong></td><td></td></tr>
  </table>
</div>

<div class="card">
  <h3>SOW Outline</h3>
  <ul>
    <li>Scope: Forest-wide AD assessment and migration to target domain/tenant</li>
    <li>Deliverables: Discovery CSVs, executive HTML report, migration plan, wave schedule</li>
    <li>Activities: Pre-migration remediation (SPNs, groups, AdminSDHolder, disabled), wave execution, cutover</li>
    <li>Assumptions: RSAT/ADMT availability, change windows, stakeholder approvals</li>
    <li>Dependencies: Trust configuration, PKI usage, GPO performance, network connectivity</li>
    <li>Acceptance: Successful migration validation and reporting sign-off</li>
  </ul>
</div>

</div>
</body>
</html>
"@

  $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

  [pscustomobject]@{
    ReportPath      = $OutputPath
    UsersTotal      = $usersTotal
    GroupsTotal     = $groupsTotal
    ComputersTotal  = $computersTotal
    ComplexityScore = $score
    LOE_Assessment  = $loeAssessment
    LOE_Remediation = $loeRemediation
    LOE_Execution   = $loeExecution
    LOE_Post        = $loePost
    LOE_Total       = $loeTotal
  }
}
