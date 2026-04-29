function New-AdMigrationPlanningReport {
  <#
    .SYNOPSIS
    Generate a migration preparation report focused on why migration is needed and what should be addressed.

    .PARAMETER DiscoveryOutputPath
    Path to the discovery output folder (root of a run).

    .PARAMETER OutputPath
    Optional path for the resulting HTML. Defaults inside DiscoveryOutputPath.
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
    $OutputPath = Join-Path $DiscoveryOutputPath "AD__Migration__Preparation__Report__$ts.html"
  }

  $runData = Get-AdDiscoveryRunSummary -RunRoot $DiscoveryOutputPath
  $summaryRow = $runData.Summary
  $riskSummary = @($runData.RiskSummary)
  $domainSummaries = @($runData.DomainSummaries)

  $usersTotal = [int]$summaryRow.UsersTotal
  $groupsTotal = [int]$summaryRow.GroupsTotal
  $computersTotal = [int]$summaryRow.ComputersTotal
  $workstationsTotal = [int]$summaryRow.WorkstationsTotal
  $serversTotal = [int]$summaryRow.ServersTotal
  $usersStale = [int]$summaryRow.UsersStaleCount
  $computersStale = [int]$summaryRow.ComputersStaleCount

  $domainCount = [int]$summaryRow.DomainsCount
  $trustCount = [int]$summaryRow.TrustCount
  $gpoCount = [int]$summaryRow.GpoCount
  $ouCount = [int]$summaryRow.OuCount
  $weakPasswordPolicyCount = [int]$summaryRow.WeakPasswordPoliciesCount
  $adminSdCount = [int]$summaryRow.AdminSdHolderImpactCount
  $usersSidHistoryCount = [int]$summaryRow.UsersSIDHistoryCount
  $upnRiskCount = [int]$summaryRow.UsersNonRoutableUPNCount
  $asrepCount = [int]$summaryRow.AsrepRoastableUsersCount
  $unconstrainedDelegationCount = [int]$summaryRow.UnconstrainedDelegationCount
  $serviceAccountCandidatesCount = [int]$summaryRow.ServiceAccountCandidatesCount
  $privilegedAccountsCount = [int]$summaryRow.PrivilegedAccountsCount
  $domainControllerCount = [int]$summaryRow.DomainControllerCount
  $adcsEnterpriseCaCount = [int]$summaryRow.AdcsEnterpriseCaCount

  $criticalRiskCount = [int](($riskSummary | Where-Object { $_.Severity -eq 'Critical' } | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) ?? 0)
  $highRiskCount = [int](($riskSummary | Where-Object { $_.Severity -eq 'High' } | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) ?? 0)
  $mediumRiskCount = [int](($riskSummary | Where-Object { $_.Severity -eq 'Medium' } | Measure-Object -Property Count -Sum | Select-Object -ExpandProperty Sum) ?? 0)

  $migrationNeedDrivers = New-Object System.Collections.Generic.List[object]
  $preparationPriorities = New-Object System.Collections.Generic.List[object]
  $environmentConsiderations = New-Object System.Collections.Generic.List[object]

  if ($usersStale -gt 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'Inactive identity footprint'
        Detail = "$usersStale user accounts have not logged on in 180+ days, indicating cleanup opportunities before moving identities into the target environment."
        Category = 'Identity hygiene'
    })
  }

  if ($computersStale -gt 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'Stale device inventory'
        Detail = "$computersStale computer accounts have not logged on in 90+ days, which can inflate migration scope and introduce avoidable cutover noise."
        Category = 'Device cleanup'
    })
  }

  if ($weakPasswordPolicyCount -gt 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'Legacy security policy gaps'
        Detail = "$weakPasswordPolicyCount default domain password policy set does not meet the toolkit baseline, reinforcing the need to modernize identity controls as part of migration preparation."
        Category = 'Security posture'
    })
  }

  if ($upnRiskCount -gt 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'UPN normalization required'
        Detail = "$upnRiskCount accounts use non-routable UPN suffixes, which commonly creates user sign-in and identity consistency issues during migration."
        Category = 'Identity normalization'
    })
  }

  if ($adminSdCount -gt 0 -or $privilegedAccountsCount -gt 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'Privileged access requires controlled handling'
        Detail = "$privilegedAccountsCount privileged accounts and $adminSdCount AdminSDHolder-protected objects require deliberate sequencing, validation, and post-migration review."
        Category = 'Privileged access'
    })
  }

  if ($usersSidHistoryCount -gt 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'Historical migration artifacts present'
        Detail = "$usersSidHistoryCount user accounts contain SID history, which should be reviewed to understand dependency chains and post-cutover cleanup expectations."
        Category = 'Legacy dependencies'
    })
  }

  if ($unconstrainedDelegationCount -gt 0 -or $asrepCount -gt 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'Directory security exposures should be reduced'
        Detail = "$unconstrainedDelegationCount unconstrained delegation objects and $asrepCount AS-REP roastable accounts indicate security debt that should be reduced before large-scale identity movement."
        Category = 'Security remediation'
    })
  }

  if ($serviceAccountCandidatesCount -gt 0) {
    $preparationPriorities.Add([pscustomobject]@{
        Priority = 'High'
        Title = 'Confirm service account ownership and application dependencies'
        Detail = "$serviceAccountCandidatesCount service account candidates were identified. These accounts typically need application owner validation, password handling, and cutover testing."
    })
  }

  if ($weakPasswordPolicyCount -gt 0 -or $upnRiskCount -gt 0 -or $usersSidHistoryCount -gt 0) {
    $preparationPriorities.Add([pscustomobject]@{
        Priority = 'High'
        Title = 'Normalize core identity attributes before migration'
        Detail = "Address password policy gaps, UPN suffix normalization, and SID history review before broad user migration waves begin."
    })
  }

  if ($usersStale -gt 0 -or $computersStale -gt 0) {
    $preparationPriorities.Add([pscustomobject]@{
        Priority = 'Medium'
        Title = 'Reduce migration scope through cleanup'
        Detail = "Disable or retire stale user and device accounts so only active objects are carried into migration planning and cutover execution."
    })
  }

  if ($adminSdCount -gt 0 -or $privilegedAccountsCount -gt 0) {
    $preparationPriorities.Add([pscustomobject]@{
        Priority = 'High'
        Title = 'Build a privileged access validation plan'
        Detail = "Validate privileged group membership, protected account behavior, and post-migration administrative access before moving highly sensitive objects."
    })
  }

  if ($unconstrainedDelegationCount -gt 0 -or $asrepCount -gt 0) {
    $preparationPriorities.Add([pscustomobject]@{
        Priority = 'Medium'
        Title = 'Resolve preventable security exposures'
        Detail = "Reduce delegation and authentication weaknesses that could complicate migration risk acceptance and post-cutover hardening."
    })
  }

  $environmentConsiderations.Add([pscustomobject]@{
      Title = 'Migration scope'
      Detail = "$domainCount domain(s), $trustCount trust relationship(s), $domainControllerCount domain controller(s), $gpoCount GPOs, and $ouCount OUs are currently in scope."
  })

  $environmentConsiderations.Add([pscustomobject]@{
      Title = 'Object inventory'
      Detail = "$usersTotal users, $groupsTotal groups, $computersTotal devices ($workstationsTotal workstations and $serversTotal servers) were discovered in the source environment."
  })

  if ($adcsEnterpriseCaCount -gt 0) {
    $environmentConsiderations.Add([pscustomobject]@{
        Title = 'PKI dependencies'
        Detail = "$adcsEnterpriseCaCount AD CS enterprise CA instance(s) were detected, which may add certificate, authentication, and sequencing considerations."
    })
  }

  if ($mediumRiskCount -gt 0 -or $highRiskCount -gt 0 -or $criticalRiskCount -gt 0) {
    $environmentConsiderations.Add([pscustomobject]@{
        Title = 'Current risk posture'
        Detail = "The discovery identified $criticalRiskCount critical, $highRiskCount high, and $mediumRiskCount medium risk indicators that should inform migration readiness and remediation planning."
    })
  }

  if ($migrationNeedDrivers.Count -eq 0) {
    $migrationNeedDrivers.Add([pscustomobject]@{
        Title = 'Modernization opportunity'
        Detail = 'The environment does not show major automated red flags, but migration still provides an opportunity to standardize identity, reduce legacy complexity, and align the directory with target-state governance.'
        Category = 'Modernization'
    })
  }

  if ($preparationPriorities.Count -eq 0) {
    $preparationPriorities.Add([pscustomobject]@{
        Priority = 'Medium'
        Title = 'Validate migration readiness with stakeholders'
        Detail = 'Use the discovery output to confirm scope, application dependencies, administrative access, and target-state assumptions before migration execution begins.'
    })
  }

  $topDomains = @(
    $domainSummaries |
      Sort-Object { [int]$_.Summary.UsersTotal } -Descending |
      Select-Object -First 5
  )

  $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AD Migration Preparation - $($summaryRow.ForestName)</title>
<style>
body{font-family:'Segoe UI',Tahoma,Arial,sans-serif;background:#f5f6f8;color:#24323f;margin:0}
.container{max-width:1200px;margin:0 auto;padding:24px}
.hdr{background:linear-gradient(135deg,#1b4965,#2c699a);color:#fff;border-radius:12px;padding:30px;margin-bottom:18px;box-shadow:0 10px 24px rgba(27,73,101,.18)}
.hdr h1{margin:0 0 8px 0;font-size:28px}
.hdr p{margin:4px 0;opacity:.92}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px;margin-bottom:18px}
.kpi{background:#fff;border-radius:10px;padding:18px;box-shadow:0 2px 8px rgba(0,0,0,.08);border-left:4px solid #2c699a}
.kpi .label{font-size:12px;color:#66788a;text-transform:uppercase;letter-spacing:.04em}
.kpi .val{font-size:30px;font-weight:700;color:#1b4965}
.card{background:#fff;border-radius:10px;padding:20px;box-shadow:0 2px 8px rgba(0,0,0,.08);margin-bottom:16px}
.card h2{margin:0 0 14px 0;color:#1b4965;font-size:20px}
.card h3{margin:0 0 8px 0;color:#245a7a;font-size:16px}
.item{padding:14px 0;border-bottom:1px solid #edf1f4}
.item:last-child{border-bottom:none}
.meta{font-size:12px;color:#66788a;font-weight:600;text-transform:uppercase;letter-spacing:.04em}
.detail{margin-top:6px}
.badge{display:inline-block;padding:4px 10px;border-radius:999px;font-size:12px;font-weight:700}
.badge.high{background:#fde2e1;color:#a33a2f}
.badge.medium{background:#fff4d6;color:#8a6500}
.badge.low{background:#dff3e4;color:#1f6f43}
.table{width:100%;border-collapse:collapse;margin-top:10px}
.table th{background:#f4f7fa;color:#245a7a;font-size:12px;text-transform:uppercase;letter-spacing:.04em;border-bottom:2px solid #2c699a;padding:10px;text-align:left}
.table td{border-bottom:1px solid #edf1f4;padding:10px}
</style>
</head>
<body>
<div class="container">
  <div class="hdr">
    <h1>Active Directory Migration Preparation</h1>
    <p>Forest: $($summaryRow.ForestName)</p>
    <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
    <p>This report explains why migration preparation is needed and highlights the conditions that should be addressed before and during migration.</p>
  </div>

  <div class="grid">
    <div class="kpi"><div class="label">Users</div><div class="val">$usersTotal</div></div>
    <div class="kpi"><div class="label">Groups</div><div class="val">$groupsTotal</div></div>
    <div class="kpi"><div class="label">Devices</div><div class="val">$computersTotal</div></div>
    <div class="kpi"><div class="label">High + Critical Risks</div><div class="val">$(($highRiskCount + $criticalRiskCount))</div></div>
  </div>

  <div class="card">
    <h2>Why Migration Preparation Is Needed</h2>
"@

  foreach ($driver in $migrationNeedDrivers) {
    $html += @"
    <div class="item">
      <div class="meta">$($driver.Category)</div>
      <h3>$($driver.Title)</h3>
      <div class="detail">$($driver.Detail)</div>
    </div>
"@
  }

  $html += @"
  </div>

  <div class="card">
    <h2>Preparation Priorities</h2>
"@

  foreach ($priority in $preparationPriorities) {
    $priorityClass = switch ($priority.Priority) {
      'High' { 'high' }
      'Medium' { 'medium' }
      default { 'low' }
    }

    $html += @"
    <div class="item">
      <span class="badge $priorityClass">$($priority.Priority)</span>
      <h3 style="display:inline-block;margin-left:10px">$($priority.Title)</h3>
      <div class="detail">$($priority.Detail)</div>
    </div>
"@
  }

  $html += @"
  </div>

  <div class="card">
    <h2>Environment Considerations</h2>
"@

  foreach ($consideration in $environmentConsiderations) {
    $html += @"
    <div class="item">
      <h3>$($consideration.Title)</h3>
      <div class="detail">$($consideration.Detail)</div>
    </div>
"@
  }

  $html += @"
  </div>

  <div class="card">
    <h2>Largest Domains in Scope</h2>
    <table class="table">
      <thead>
        <tr>
          <th>Domain</th>
          <th>Users</th>
          <th>Groups</th>
          <th>Devices</th>
          <th>Stale Users</th>
          <th>Stale Devices</th>
        </tr>
      </thead>
      <tbody>
"@

  foreach ($domain in $topDomains) {
    $s = $domain.Summary
    $html += @"
        <tr>
          <td>$($domain.Domain)</td>
          <td>$([int]$s.UsersTotal)</td>
          <td>$([int]$s.GroupsTotal)</td>
          <td>$([int]$s.ComputersTotal)</td>
          <td>$([int]$s.UsersStaleCount)</td>
          <td>$([int]$s.ComputersStaleCount)</td>
        </tr>
"@
  }

  $html += @"
      </tbody>
    </table>
  </div>
</div>
</body>
</html>
"@

  $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

  [pscustomobject]@{
    ReportPath             = $OutputPath
    UsersTotal             = $usersTotal
    GroupsTotal            = $groupsTotal
    ComputersTotal         = $computersTotal
    MigrationNeedCount     = $migrationNeedDrivers.Count
    PreparationPriorityCount = $preparationPriorities.Count
    HighRiskCount          = $highRiskCount
    CriticalRiskCount      = $criticalRiskCount
  }
}
