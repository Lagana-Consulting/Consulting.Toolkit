function Get-LcAssessmentSummary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$ForestName,

    [Parameter(Mandatory)]
    [array]$AllUsers,

    [Parameter(Mandatory)]
    [array]$AllComputers,

    [Parameter(Mandatory)]
    [array]$AllGroups,

    [Parameter(Mandatory)]
    [array]$PrivilegedAccounts,

    [int]$StaleUserThresholdDays = 180,

    [int]$StaleComputerThresholdDays = 90
  )

  $forest = Get-LcAdForest -ForestName $ForestName
  $domains = Get-LcAdDomains -Forest $forest

  $usersTotal = $AllUsers.Count
  $groupsTotal = $AllGroups.Count
  $computersTotal = $AllComputers.Count

  # Stale users (LastLogonDays > threshold)
  $usersStale = @($AllUsers | Where-Object {
    $_.LastLogonDays -and [int]$_.LastLogonDays -gt $StaleUserThresholdDays
  })
  $usersStaleCount = $usersStale.Count
  $usersStalePct = if ($usersTotal -gt 0) { [math]::Round(($usersStaleCount / $usersTotal) * 100, 2) } else { 0 }

  # Stale computers
  $computersStale = @($AllComputers | Where-Object {
    $_.LastLogonDays -and [int]$_.LastLogonDays -gt $StaleComputerThresholdDays
  })
  $computersStaleCount = $computersStale.Count
  $computersStalePct = if ($computersTotal -gt 0) { [math]::Round(($computersStaleCount / $computersTotal) * 100, 2) } else { 0 }

  # SID history
  $usersSidHistory = @($AllUsers | Where-Object {
    $_.SidHistoryCount -and [int]$_.SidHistoryCount -gt 0
  })
  $usersSidHistoryCount = $usersSidHistory.Count
  $usersSidHistoryPct = if ($usersTotal -gt 0) { [math]::Round(($usersSidHistoryCount / $usersTotal) * 100, 2) } else { 0 }

  # Non-routable UPN
  $usersNonRoutableUpn = @($AllUsers | Where-Object {
    $_.IsNonRoutableUpnSuffix -eq $true
  })
  $usersNonRoutableUpnCount = $usersNonRoutableUpn.Count
  $usersNonRoutableUpnPct = if ($usersTotal -gt 0) { [math]::Round(($usersNonRoutableUpnCount / $usersTotal) * 100, 2) } else { 0 }

  # RC4-only objects (EncryptionRisk = High and no AES)
  $allObjects = @($AllUsers) + @($AllComputers)
  $objectsRC4Only = @($allObjects | Where-Object {
    $_.EncryptionRisk -eq 'High' -and $_.EncryptionTypes -notmatch 'AES'
  })
  $objectsRC4OnlyCount = $objectsRC4Only.Count
  $objectsRC4OnlyPct = if ($allObjects.Count -gt 0) { [math]::Round(($objectsRC4OnlyCount / $allObjects.Count) * 100, 2) } else { 0 }

  [pscustomobject]@{
    RunTimestamp                = (Get-Date).ToString('M/d/yyyy h:mm:ss tt')
    ForestName                  = [string]$forest.Name
    ForestRootDomain            = [string]$forest.RootDomain
    DomainsCount                = $domains.Count
    UsersTotal                  = $usersTotal
    GroupsTotal                 = $groupsTotal
    ComputersTotal              = $computersTotal
    UsersStaleCount             = $usersStaleCount
    UsersStalePct               = $usersStalePct
    ComputersStaleCount         = $computersStaleCount
    ComputersStalePct           = $computersStalePct
    UsersSIDHistoryCount        = $usersSidHistoryCount
    UsersSIDHistoryPct          = $usersSidHistoryPct
    UsersNonRoutableUPNCount    = $usersNonRoutableUpnCount
    UsersNonRoutableUPNPct      = $usersNonRoutableUpnPct
    ObjectsRC4OnlyCount         = $objectsRC4OnlyCount
    ObjectsRC4OnlyPct           = $objectsRC4OnlyPct
    PrivilegedAccountsCount     = $PrivilegedAccounts.Count
  }
}
