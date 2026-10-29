function Get-AdGroupMembersRecursive {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$GroupDn,
    [Parameter(Mandatory)][string]$Server
  )

  if (-not (Get-Command Get-ADGroupMember -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADGroupMember missing)."
  }

  $seenGroups = @{}
  $results = @()

  $stack = New-Object System.Collections.Generic.Stack[string]
  $stack.Push($GroupDn)

  while ($stack.Count -gt 0) {
    $current = $stack.Pop()
    if ($seenGroups.ContainsKey($current)) { continue }
    $seenGroups[$current] = $true

    $members = @()
    try {
      $members = @(Get-ADGroupMember -Identity $current -Server $Server -ErrorAction Stop)
    } catch {
      Write-AdDiscoveryCollectionIssue -Message "Could not expand group membership: $current" -ErrorRecord $_ -Details @{ GroupDn = $current; Server = $Server }
      continue
    }

    foreach ($m in $members) {
      if ($m.objectClass -eq 'group') {
        $stack.Push([string]$m.DistinguishedName)
      } elseif ($m.objectClass -eq 'user') {
        $results += $m
      }
    }
  }

  return @($results)
}

function Get-AdGroupMembershipMemberDetail {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$DomainFqdn,
    [AllowEmptyString()][string]$Server,
    [Parameter(Mandatory)]$Group,
    [Parameter(Mandatory)][string]$MemberDn,
    [Parameter(Mandatory)][datetime]$Now,
    [int]$InactiveDays = 180
  )

  $member = $null
  $lookupError = ''

  try {
    $params = @{
      Identity    = $MemberDn
      Properties  = @('SamAccountName', 'Name', 'ObjectClass', 'userAccountControl', 'LastLogonTimestamp', 'Description', 'DistinguishedName')
      ErrorAction = 'Stop'
    }
    if (-not [string]::IsNullOrWhiteSpace($Server)) {
      $params.Server = $Server
    }

    $member = Get-ADObject @params
  }
  catch {
    $lookupError = $_.Exception.Message
    Write-AdDiscoveryCollectionIssue -Message "Could not read group member: $MemberDn" -ErrorRecord $_ -Details @{ GroupDn = $Group.DistinguishedName; MemberDn = $MemberDn; Server = $Server }
  }

  $lastLogonUtc = $null
  $lastLogonDays = $null
  if ($member -and $member.PSObject.Properties['LastLogonTimestamp'] -and $member.LastLogonTimestamp) {
    try {
      $lastLogonUtc = [DateTime]::FromFileTimeUtc([int64]$member.LastLogonTimestamp)
      $lastLogonDays = [int]([TimeSpan]($Now.ToUniversalTime() - $lastLogonUtc)).TotalDays
    }
    catch {
      Write-AdDiscoveryCollectionIssue -Message "Could not interpret the last-logon timestamp for $MemberDn" -ErrorRecord $_
      $lastLogonUtc = $null
      $lastLogonDays = $null
    }
  }

  $enabledValue = if ($member -and $member.PSObject.Properties['userAccountControl'] -and $null -ne $member.userAccountControl) {
    ($member.userAccountControl -band 2) -eq 0
  } elseif ($member -and $member.PSObject.Properties['Enabled']) {
    $member.Enabled
  } else { $null }
  $isDisabled = if ($null -eq $enabledValue) { $false } else { -not [bool]$enabledValue }
  $isInactive = if ($null -ne $lastLogonDays) { $lastLogonDays -gt $InactiveDays } else { $false }

  [pscustomobject]@{
    DomainFqdn                  = $DomainFqdn
    GroupName                   = [string]$Group.Name
    GroupSamAccountName         = [string]$Group.SamAccountName
    GroupDistinguishedName      = [string]$Group.DistinguishedName
    GroupCategory               = [string]$Group.GroupCategory
    GroupScope                  = [string]$Group.GroupScope
    GroupMemberCount            = @($Group.Members).Count
    MemberName                  = if ($member) { [string]$member.Name } else { '' }
    MemberSamAccountName        = if ($member) { [string]$member.SamAccountName } else { '' }
    MemberObjectClass           = if ($member) { [string]$member.ObjectClass } else { '' }
    MemberDistinguishedName     = $MemberDn
    MemberEnabled               = if ($null -eq $enabledValue) { '' } else { [string]$enabledValue }
    LastLogonTimestampUtc       = if ($lastLogonUtc) { $lastLogonUtc.ToString('o') } else { '' }
    LastLogonDays               = if ($null -eq $lastLogonDays) { '' } else { [string]$lastLogonDays }
    InactiveThresholdDays       = $InactiveDays
    IsDisabled                  = [bool]$isDisabled
    IsInactive                  = [bool]$isInactive
    FindingReason               = if ($isDisabled -and $isInactive) { 'Disabled;Inactive' } elseif ($isDisabled) { 'Disabled' } elseif ($isInactive) { 'Inactive' } else { '' }
    LookupError                 = $lookupError
  }
}

function New-AdGroupMembershipSummaryRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$DomainFqdn,
    [Parameter(Mandatory)]$Group,
    [int]$MemberCount
  )

  [pscustomobject]@{
    DomainFqdn             = $DomainFqdn
    GroupName              = [string]$Group.Name
    GroupSamAccountName    = [string]$Group.SamAccountName
    GroupDistinguishedName = [string]$Group.DistinguishedName
    GroupCategory          = [string]$Group.GroupCategory
    GroupScope             = [string]$Group.GroupScope
    MemberCount            = $MemberCount
    WhenCreated            = $Group.WhenCreated
    WhenChanged            = $Group.WhenChanged
    Description            = [string]$Group.Description
  }
}

function New-AdGroupMembershipSingleMemberRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$DomainFqdn,
    [Parameter(Mandatory)]$Group,
    [int]$MemberCount,
    [AllowNull()]$Member
  )

  [pscustomobject]@{
    DomainFqdn             = $DomainFqdn
    GroupName              = [string]$Group.Name
    GroupSamAccountName    = [string]$Group.SamAccountName
    GroupDistinguishedName = [string]$Group.DistinguishedName
    GroupCategory          = [string]$Group.GroupCategory
    GroupScope             = [string]$Group.GroupScope
    MemberCount            = $MemberCount
    MemberName             = if ($Member) { [string]$Member.MemberName } else { '' }
    MemberSamAccountName   = if ($Member) { [string]$Member.MemberSamAccountName } else { '' }
    MemberObjectClass      = if ($Member) { [string]$Member.MemberObjectClass } else { '' }
    MemberDistinguishedName = if ($Member) { [string]$Member.MemberDistinguishedName } else { '' }
    MemberEnabled          = if ($Member) { [string]$Member.MemberEnabled } else { '' }
    LastLogonTimestampUtc  = if ($Member) { [string]$Member.LastLogonTimestampUtc } else { '' }
    LastLogonDays          = if ($Member) { [string]$Member.LastLogonDays } else { '' }
    WhenCreated            = $Group.WhenCreated
    WhenChanged            = $Group.WhenChanged
    Description            = [string]$Group.Description
  }
}
