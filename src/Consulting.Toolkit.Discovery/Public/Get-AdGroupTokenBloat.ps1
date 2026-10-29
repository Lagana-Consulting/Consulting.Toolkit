function Get-AdGroupTokenBloat {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [array]$AllUsers,

    [int]$WarningSidCount = 800,
    [int]$CriticalSidCount = 1015
  )

  $results = @()

  foreach ($user in $AllUsers) {
    # Estimate token size based on:
    # - User's SID (1)
    # - Primary group SID (1)
    # - Group memberships (direct + nested)
    # - SID history count

    $tokenSidCount = 2  # User SID + Primary Group SID

    # Add direct group memberships (if MemberOf is available)
    if ($user.PSObject.Properties['MemberOf'] -and $user.MemberOf) {
      $memberOfCount = if ($user.MemberOf -is [array]) { $user.MemberOf.Count } else { 1 }
      $tokenSidCount += $memberOfCount
    }

    # Add SID history
    if ($user.PSObject.Properties['SidHistoryCount'] -and $user.SidHistoryCount) {
      $tokenSidCount += [int]$user.SidHistoryCount
    }

    # Note: This is a conservative estimate. Actual token size includes nested group memberships
    # which would require recursive group expansion. This estimate uses direct memberships only.

    $status = 'OK'
    $severity = 'Low'
    if ($tokenSidCount -ge $CriticalSidCount) {
      $status = 'Critical'
      $severity = 'High'
    } elseif ($tokenSidCount -ge $WarningSidCount) {
      $status = 'Warning'
      $severity = 'Medium'
    }

    # Only return users approaching or exceeding thresholds
    if ($tokenSidCount -ge $WarningSidCount) {
      $results += [pscustomobject]@{
        DomainFqdn          = $user.DomainFqdn
        SamAccountName      = $user.SamAccountName
        UserPrincipalName   = if ($user.PSObject.Properties['UserPrincipalName']) { $user.UserPrincipalName } else { '' }
        DistinguishedName   = $user.DistinguishedName
        EstimatedSidCount   = $tokenSidCount
        DirectGroupCount    = if ($user.PSObject.Properties['MemberOf'] -and $user.MemberOf) {
                                if ($user.MemberOf -is [array]) { $user.MemberOf.Count } else { 1 }
                              } else { 0 }
        SidHistoryCount     = if ($user.PSObject.Properties['SidHistoryCount']) { [int]$user.SidHistoryCount } else { 0 }
        Status              = $status
        Severity            = $severity
        Recommendation      = if ($status -eq 'Critical') { 'Remove unnecessary group memberships and SID history before migration' }
                             elseif ($status -eq 'Warning') { 'Review group memberships for optimization' }
                             else { 'No action needed' }
      }
    }
  }

  return $results
}
