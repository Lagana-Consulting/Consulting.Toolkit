function New-LcMigrationReadinessChecklist {
  <#
  .SYNOPSIS
  Generate migration readiness validation checklist based on comparison and risk analysis.

  .DESCRIPTION
  Analyzes discovery outputs and generates a pre-cutover validation checklist covering:
  - Object reconciliation (users, groups, computers)
  - Trust relationships and domain configuration
  - Special objects (service accounts, privileged groups)
  - Network and replication readiness
  - Application readiness

  .PARAMETER SourceRunRoot
  Path to source environment discovery output root folder

  .PARAMETER TargetRunRoot
  Path to target environment discovery output root folder

  .PARAMETER OutputPath
  Path where HTML checklist will be saved

  .PARAMETER CustomerName
  Customer name to include in report header

  .EXAMPLE
  New-LcMigrationReadinessChecklist -SourceRunRoot "c:\reports\ADOnly_..." -TargetRunRoot "c:\reports\ADOnly__target_..." -OutputPath "c:\reports\Checklist.html"
  #>

  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$SourceRunRoot,

    [Parameter(Mandatory)]
    [string]$TargetRunRoot,

    [string]$OutputPath,
    [string]$CustomerName = "Organization"
  )

  if (-not (Test-Path -LiteralPath $SourceRunRoot)) {
    throw "Source run root not found: $SourceRunRoot"
  }
  if (-not (Test-Path -LiteralPath $TargetRunRoot)) {
    throw "Target run root not found: $TargetRunRoot"
  }

  # Determine output path
  if (-not $OutputPath) {
    $timestamp = (Get-LcTimestamp -Format File)
    $OutputPath = Join-Path $SourceRunRoot "LC__Migration__Readiness__Checklist__$timestamp.html"
  }

  # Helper to safely import CSV
  function Import-CsvSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try {
      return @(Import-Csv -Path $Path -ErrorAction Stop)
    } catch {
      return @()
    }
  }

  # Load assessments
  $sourceAssess = Import-CsvSafe (Join-Path $SourceRunRoot 'LC__AD__Assessment__Summary__Forest.csv') | Select-Object -First 1
  $targetAssess = Import-CsvSafe (Join-Path $TargetRunRoot 'LC__AD__Assessment__Summary__Forest.csv') | Select-Object -First 1

  # Load risk flags
  $sourceRiskFlags = Import-CsvSafe (Join-Path $SourceRunRoot 'LC__AD__Migration__RiskFlagsSummary__Forest.csv')
  $targetRiskFlags = Import-CsvSafe (Join-Path $TargetRunRoot 'LC__AD__Migration__RiskFlagsSummary__Forest.csv')

  # Parse risk flag counts
  $sourceCritical = @($sourceRiskFlags | Where-Object { $_.Flag -match 'Critical' } | Measure-Object Count -Sum).Sum
  $sourceHigh = @($sourceRiskFlags | Where-Object { $_.Flag -match 'High' } | Measure-Object Count -Sum).Sum
  $targetCritical = @($targetRiskFlags | Where-Object { $_.Flag -match 'Critical' } | Measure-Object Count -Sum).Sum
  $targetHigh = @($targetRiskFlags | Where-Object { $_.Flag -match 'High' } | Measure-Object Count -Sum).Sum

  # Build checklist items
  $checklistItems = @(
    @{
      Category = "Object Reconciliation"
      Items    = @(
        @{
          Item   = "All source users migrated to target";
          Status = if ([int]$sourceAssess.TotalUsers -le [int]$targetAssess.TotalUsers) { "Pass" } else { "Fail" };
          Note   = "Source: $($sourceAssess.TotalUsers) → Target: $($targetAssess.TotalUsers)"
        },
        @{
          Item   = "All source groups migrated to target";
          Status = if ([int]$sourceAssess.TotalGroups -le [int]$targetAssess.TotalGroups) { "Pass" } else { "Fail" };
          Note   = "Source: $($sourceAssess.TotalGroups) → Target: $($targetAssess.TotalGroups)"
        },
        @{
          Item   = "All source computers migrated to target";
          Status = if ([int]$sourceAssess.TotalComputers -le [int]$targetAssess.TotalComputers) { "Pass" } else { "Fail" };
          Note   = "Source: $($sourceAssess.TotalComputers) → Target: $($targetAssess.TotalComputers)"
        }
      )
    },
    @{
      Category = "Domain Configuration"
      Items    = @(
        @{
          Item   = "Target domain functional level set correctly";
          Status = "Manual"
          Note   = "Verify DFL matches source or target migration requirement"
        },
        @{
          Item   = "All domain trusts configured";
          Status = "Manual"
          Note   = "Review trust relationships between source and target domains"
        },
        @{
          Item   = "UPN suffixes synchronized";
          Status = "Manual"
          Note   = "Verify all source UPN suffixes present in target forest"
        }
      )
    },
    @{
      Category = "Special Objects & Privileges"
      Items    = @(
        @{
          Item   = "Service accounts migrated";
          Status = "Manual"
          Note   = "Verify all source service accounts present with correct permissions"
        },
        @{
          Item   = "Privileged groups reconciled";
          Status = "Manual"
          Note   = "Cross-check Enterprise Admins, Domain Admins, Schema Admins"
        },
        @{
          Item   = "Exchange-specific groups migrated (if applicable)";
          Status = "Manual"
          Note   = "Organization_Management, Exchange Trusted Subsystem, etc."
        }
      )
    },
    @{
      Category = "Risk Mitigation"
      Items    = @(
        @{
          Item   = "Critical risk flags resolved in target";
          Status = if ($targetCritical -eq 0) { "Pass" } else { "Fail" };
          Note   = "Source critical: $sourceCritical → Target critical: $targetCritical"
        },
        @{
          Item   = "High risk items addressed";
          Status = "Manual"
          Note   = "Target has $targetHigh high-risk items; verify remediation plan"
        },
        @{
          Item   = "Stale accounts archived/disabled";
          Status = "Manual"
          Note   = "Verify inactive accounts (90+ days) are disabled in target"
        }
      )
    },
    @{
      Category = "Network & Replication"
      Items    = @(
        @{
          Item   = "All source domain controllers replicating";
          Status = "Manual"
          Note   = "Verify replication health in source forest"
        },
        @{
          Item   = "All target domain controllers replicating";
          Status = "Manual"
          Note   = "Verify replication health in target forest"
        },
        @{
          Item   = "Network connectivity validated";
          Status = "Manual"
          Note   = "Test network paths between all sites"
        }
      )
    },
    @{
      Category = "Application Readiness"
      Items    = @(
        @{
          Item   = "Applications tested in target environment";
          Status = "Manual"
          Note   = "Execute application compatibility validation"
        },
        @{
          Item   = "Group Policy Objects applied correctly";
          Status = "Manual"
          Note   = "Verify GPO links and inheritance in target"
        },
        @{
          Item   = "Permissions verified on resources";
          Status = "Manual"
          Note   = "Spot-check file shares, SQL, Exchange resources"
        }
      )
    },
    @{
      Category = "Cutover Preparation"
      Items    = @(
        @{
          Item   = "Rollback plan documented";
          Status = "Manual"
          Note   = "Document rollback procedures and communication plan"
        },
        @{
          Item   = "Monitoring configured in target";
          Status = "Manual"
          Note   = "Enable AD replication monitoring and alerts"
        },
        @{
          Item   = "Stakeholder sign-off obtained";
          Status = "Manual"
          Note   = "Document approval from business/technical stakeholders"
        }
      )
    }
  )

  # Build HTML without here-strings (to avoid parser errors)
  $htmlHeader = @(
    "<!DOCTYPE html>",
    "<html lang=`"en`">",
    "<head>",
    "  <meta charset=`"UTF-8`">",
    "  <meta name=`"viewport`" content=`"width=device-width, initial-scale=1.0`">",
    "  <title>Migration Readiness Checklist</title>",
    "  <style>",
    "    * { margin: 0; padding: 0; box-sizing: border-box; }",
    "    body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; color: #333; line-height: 1.6; }",
    "    .container { max-width: 1200px; margin: 0 auto; padding: 20px; background: white; box-shadow: 0 0 10px rgba(0,0,0,0.1); }",
    "    header { border-bottom: 4px solid #0078d4; padding-bottom: 20px; margin-bottom: 30px; }",
    "    h1 { color: #0078d4; font-size: 28px; margin-bottom: 5px; }",
    "    .subtitle { color: #666; font-size: 14px; }",
    "    .section { margin-bottom: 40px; }",
    "    .section h2 { color: #0078d4; font-size: 18px; margin: 20px 0 15px 0; border-left: 4px solid #0078d4; padding-left: 10px; background: #f0f0f0; padding: 10px; }",
    "    .checklist { list-style: none; }",
    "    .checklist-item { padding: 12px; margin: 8px 0; border-left: 4px solid #999; background: #fafafa; display: flex; align-items: flex-start; }",
    "    .checklist-item.pass { border-left-color: #107c10; background: #f1f9f1; }",
    "    .checklist-item.fail { border-left-color: #d83b01; background: #fef3f0; }",
    "    .checklist-item.manual { border-left-color: #0078d4; background: #eff6fc; }",
    "    .checkbox { width: 20px; height: 20px; margin-right: 12px; flex-shrink: 0; border-radius: 3px; display: flex; align-items: center; justify-content: center; font-weight: 700; color: white; font-size: 12px; }",
    "    .item-text { flex: 1; }",
    "    .item-title { font-weight: 600; margin-bottom: 4px; }",
    "    .item-note { font-size: 12px; color: #666; }",
    "    .status-badge { display: inline-block; padding: 4px 12px; border-radius: 3px; font-size: 11px; font-weight: 600; margin-left: 10px; }",
    "    .status-pass { background: #d4ffd4; color: #107c10; }",
    "    .status-fail { background: #ffd4d0; color: #d83b01; }",
    "    .status-manual { background: #d4e8ff; color: #0078d4; }",
    "    .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin: 20px 0; }",
    "    .summary-card { background: #f0f0f0; padding: 15px; border-radius: 5px; text-align: center; }",
    "    .summary-card .value { font-size: 24px; font-weight: 700; }",
    "    .summary-card .label { font-size: 12px; color: #666; margin-top: 5px; }",
    "    footer { border-top: 1px solid #ddd; padding-top: 15px; margin-top: 30px; text-align: center; color: #999; font-size: 12px; }",
    "    .print-section { page-break-inside: avoid; }",
    "    @media print {",
    "      body { background: white; }",
    "      .container { box-shadow: none; }",
    "    }",
    "  </style>",
    "</head>",
    "<body>",
    "  <div class=`"container`">",
    "    <header>",
    "      <h1>Migration Readiness Validation Checklist</h1>",
    "      <p class=`"subtitle`">$CustomerName | Generated $(Get-Date -Format 'MMMM d, yyyy HH:mm:ss')</p>",
    "    </header>",
    "",
    "    <div class=`"section`">",
    "      <h2>Readiness Summary</h2>",
    "      <div class=`"summary`">",
    "        <div class=`"summary-card`">",
    "          <div class=`"value`">$(($checklistItems.Items | Where-Object { $_.Status -eq 'Pass' } | Measure-Object).Count)</div>",
    "          <div class=`"label`">Automatic Pass</div>",
    "        </div>",
    "        <div class=`"summary-card`">",
    "          <div class=`"value`">$(($checklistItems.Items | Where-Object { $_.Status -eq 'Fail' } | Measure-Object).Count)</div>",
    "          <div class=`"label`">Failures Detected</div>",
    "        </div>",
    "        <div class=`"summary-card`">",
    "          <div class=`"value`">$(($checklistItems.Items | Where-Object { $_.Status -eq 'Manual' } | Measure-Object).Count)</div>",
    "          <div class=`"label`">Manual Review</div>",
    "        </div>",
    "      </div>",
    "    </div>"
  )

  $htmlContent = ($htmlHeader -join "`n")

  foreach ($section in $checklistItems) {
    $htmlContent += "
    <div class='section print-section'>
      <h2>$($section.Category)</h2>
      <ul class='checklist'>
"

    foreach ($item in $section.Items) {
      $statusClass = $item.Status.ToLower()
      $checkboxClass = $statusClass
      $badgeClass = "status-$statusClass"

      $htmlContent += "
        <li class='checklist-item $statusClass'>
          <div class='checkbox $checkboxClass'></div>
          <div class='item-text'>
            <div class='item-title'>
              $($item.Item)
              <span class='status-badge $badgeClass'>$($item.Status)</span>
            </div>
            <div class='item-note'>$($item.Note)</div>
          </div>
        </li>
"
    }

    $htmlContent += "
      </ul>
    </div>
"
  }

  $footer = @(
    "    <div class='section'>",
    "      <h2>Recommendations</h2>",
    "      <ol style='margin-left: 20px; line-height: 1.8;'>",
    "        <li><strong>Address Failures First:</strong> Any 'Fail' items must be resolved before cutover. Review detailed discovery outputs to understand root cause.</li>",
    "        <li><strong>Complete Manual Reviews:</strong> These items require human verification. Create a separate verification log with sign-offs.</li>",
    "        <li><strong>Test Cutover Sequence:</strong> Dry-run the migration in a lab environment using the discovered topology and object counts.</li>",
    "        <li><strong>Monitor Replication:</strong> After cutover, monitor all replication partners for convergence within expected timeframe.</li>",
    "        <li><strong>Validate Applications:</strong> Execute smoke tests on key applications post-cutover before full user access.</li>",
    "        <li><strong>Maintain Rollback Readiness:</strong> Keep rollback procedures accessible and tested until full production validation complete.</li>",
    "      </ol>",
    "    </div>",
    "",
    "    <footer>",
    "      <p>Lagana Consulting Toolkit | Migration Readiness Assessment | Print-friendly version available</p>",
    "    </footer>",
    "  </div>",
    "</body>",
    "</html>"
  )

  $htmlContent += ("`n" + ($footer -join "`n"))

  # Save HTML
  $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
  Write-Host "Readiness checklist generated: $OutputPath" -ForegroundColor Green

  return [pscustomobject]@{
    ChecklistPath = $OutputPath
    PassItems     = @($checklistItems.Items | Where-Object { $_.Status -eq 'Pass' }).Count
    FailItems     = @($checklistItems.Items | Where-Object { $_.Status -eq 'Fail' }).Count
    ManualItems   = @($checklistItems.Items | Where-Object { $_.Status -eq 'Manual' }).Count
  }
}
