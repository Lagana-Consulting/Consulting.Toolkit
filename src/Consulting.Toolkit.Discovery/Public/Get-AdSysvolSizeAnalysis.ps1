function Get-AdSysvolSizeAnalysis {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$DomainFqdn,

    [string]$Server,

    [int]$WarningSizeGB = 1,
    [int]$CriticalSizeGB = 5
  )

  if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools."
  }

  $results = @()

  try {
    $ctx = Get-AdAdDomainContext -DomainFqdn $DomainFqdn -Server $Server
    $serverTarget = $ctx.Server

    # SYSVOL path: \\domain\SYSVOL\domain
    $sysvolPath = "\\$serverTarget\SYSVOL\$DomainFqdn"

    try {
      if (Test-Path $sysvolPath -ErrorAction Stop) {
        # Calculate total size
        $totalSizeBytes = (Get-ChildItem -Path $sysvolPath -Recurse -File -ErrorAction Stop |
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
          (Get-ChildItem -Path $policiesPath -Directory -ErrorAction Stop | Where-Object { $_.Name -match '^\{[A-F0-9\-]+\}$' }).Count
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
        Write-AdDiscoveryCollectionIssue -Message "SYSVOL path is inaccessible: $sysvolPath"
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
      Write-AdDiscoveryCollectionIssue -Message "Failed to measure SYSVOL size for $DomainFqdn." -ErrorRecord $_
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
    throw
  }

  return $results
}
