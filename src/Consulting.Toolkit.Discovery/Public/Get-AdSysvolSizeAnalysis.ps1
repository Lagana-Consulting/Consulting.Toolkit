function Get-AdSysvolSizeAnalysis {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$DomainFqdn,

    [string]$Server,

    [int]$WarningSizeGB = 1,
    [int]$CriticalSizeGB = 5
  )

  if (-not (Get-Command Get-ADDomainController -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools."
  }

  $results = @()

  try {
    # Get a writable DC for the domain
    $dc = Get-ADDomainController -DomainName $DomainFqdn -Discover -Service PrimaryDC -ErrorAction Stop
    $dcName = $dc.HostName.Split('.')[0]

    # SYSVOL path: \\domain\SYSVOL\domain
    $sysvolPath = "\\$DomainFqdn\SYSVOL\$DomainFqdn"

    try {
      if (Test-Path $sysvolPath -ErrorAction SilentlyContinue) {
        # Calculate total size
        $totalSizeBytes = (Get-ChildItem -Path $sysvolPath -Recurse -File -ErrorAction SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum

        $totalSizeGB = [math]::Round($totalSizeBytes / 1GB, 2)

        $status = 'OK'
        if ($totalSizeGB -ge $CriticalSizeGB) {
          $status = 'Critical'
        } elseif ($totalSizeGB -ge $WarningSizeGB) {
          $status = 'Warning'
        }

        # Count GPOs in SYSVOL
        $policiesPath = Join-Path $sysvolPath 'Policies'
        $gpoFolders = if (Test-Path $policiesPath) {
          (Get-ChildItem -Path $policiesPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\{[A-F0-9\-]+\}$' }).Count
        } else { 0 }

        $results += [pscustomobject]@{
          DomainFqdn     = $DomainFqdn
          SysvolPath     = $sysvolPath
          SizeGB         = $totalSizeGB
          GpoFolderCount = $gpoFolders
          Status         = $status
          Recommendation = if ($status -eq 'Critical') { 'Review for obsolete files, large GPO preferences, or excessive scripts' }
                          elseif ($status -eq 'Warning') { 'Monitor size growth' }
                          else { 'No action needed' }
        }
      } else {
        $results += [pscustomobject]@{
          DomainFqdn     = $DomainFqdn
          SysvolPath     = $sysvolPath
          SizeGB         = 0
          GpoFolderCount = 0
          Status         = 'Inaccessible'
          Recommendation = 'SYSVOL path not accessible from this location'
        }
      }
    } catch {
      Write-Warning "Failed to measure SYSVOL size: $($_.Exception.Message)"
      $results += [pscustomobject]@{
        DomainFqdn     = $DomainFqdn
        SysvolPath     = $sysvolPath
        SizeGB         = 0
        GpoFolderCount = 0
        Status         = 'Error'
        Recommendation = $_.Exception.Message
      }
    }

  } catch {
    Write-Warning "Failed to analyze SYSVOL for $DomainFqdn`: $($_.Exception.Message)"
  }

  return $results
}
