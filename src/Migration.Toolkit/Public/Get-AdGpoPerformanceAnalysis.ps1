function Get-AdGpoPerformanceAnalysis {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [array]$AllGpos,

    [int]$WarningSizeKB = 5120,
    [int]$CriticalSizeKB = 10240
  )

  $results = @()

  foreach ($gpo in $AllGpos) {
    # Calculate total version changes (user + computer)
    $userVersion = if ($gpo.PSObject.Properties['UserVersion']) { $gpo.UserVersion } else { 0 }
    $computerVersion = if ($gpo.PSObject.Properties['ComputerVersion']) { $gpo.ComputerVersion } else { 0 }
    $totalVersions = $userVersion + $computerVersion

    # Assess GPO size if SysvolSize is available (would need to be added to Get-AdGpoInventory)
    # For now, we'll assess based on version count and link count as complexity indicators

    $linkCount = if ($gpo.PSObject.Properties['LinkCount']) { [int]$gpo.LinkCount } else { 0 }

    # Complexity scoring
    $complexityScore = 0
    if ($totalVersions -gt 1000) { $complexityScore += 3 }
    elseif ($totalVersions -gt 500) { $complexityScore += 2 }
    elseif ($totalVersions -gt 100) { $complexityScore += 1 }

    if ($linkCount -gt 10) { $complexityScore += 2 }
    elseif ($linkCount -gt 5) { $complexityScore += 1 }

    # Check if GPO has WMI filter (can slow processing)
    $hasWmiFilter = if ($gpo.PSObject.Properties['WmiFilter'] -and $gpo.WmiFilter -and $gpo.WmiFilter -ne 'None') { $true } else { $false }
    if ($hasWmiFilter) { $complexityScore += 2 }

    $status = 'OK'
    $severity = 'Low'
    if ($complexityScore -ge 6) {
      $status = 'High Complexity'
      $severity = 'High'
    } elseif ($complexityScore -ge 4) {
      $status = 'Medium Complexity'
      $severity = 'Medium'
    }

    # Only return GPOs with notable complexity
    if ($complexityScore -ge 3) {
      $performanceNotes = @()
      if ($totalVersions -gt 500) { $performanceNotes += "High version count ($totalVersions)" }
      if ($linkCount -gt 5) { $performanceNotes += "Multiple links ($linkCount)" }
      if ($hasWmiFilter) { $performanceNotes += 'WMI filter applied' }

      $results += [pscustomobject]@{
        GpoName            = $gpo.DisplayName
        DomainFqdn         = $gpo.DomainFqdn
        GpoId              = $gpo.GpoId
        UserVersion        = $userVersion
        ComputerVersion    = $computerVersion
        TotalVersions      = $totalVersions
        LinkCount          = $linkCount
        HasWmiFilter       = $hasWmiFilter
        ComplexityScore    = $complexityScore
        Status             = $status
        Severity           = $severity
        PerformanceNotes   = ($performanceNotes -join '; ')
        Recommendation     = if ($status -eq 'High Complexity') { 'Review for consolidation or simplification to improve GPO processing time' }
                            elseif ($status -eq 'Medium Complexity') { 'Monitor GPO application time in production' }
                            else { 'No action needed' }
      }
    }
  }

  return $results
}
