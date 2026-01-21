function Get-LcDuplicateObjectsForAdmt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [array]$AllUsers,

    [Parameter(Mandatory)]
    [array]$AllComputers,

    [Parameter(Mandatory)]
    [array]$AllGroups
  )

  $results = @()

  # Check for duplicate sAMAccountNames across domains
  $allObjects = @($AllUsers) + @($AllComputers) + @($AllGroups)

  $samDuplicates = $allObjects | Group-Object -Property SamAccountName | Where-Object { $_.Count -gt 1 }

  foreach ($dup in $samDuplicates) {
    $conflictingDomains = ($dup.Group | Select-Object -ExpandProperty DomainFqdn -Unique) -join '; '
    $conflictingDNs = ($dup.Group | Select-Object -ExpandProperty DistinguishedName) -join ' | '
    $objectClasses = ($dup.Group | Select-Object -ExpandProperty ObjectClass -Unique) -join '; '

    $results += [pscustomobject]@{
      ConflictType       = 'SamAccountName'
      ConflictValue      = $dup.Name
      ObjectClasses      = $objectClasses
      ConflictCount      = $dup.Count
      ConflictingDomains = $conflictingDomains
      ConflictingDNs     = $conflictingDNs
      Severity           = 'High'
      Recommendation     = 'Rename before ADMT migration to prevent conflicts'
    }
  }

  # Check for duplicate UPNs (users only)
  $upnDuplicates = $AllUsers | Where-Object { $_.UserPrincipalName } |
    Group-Object -Property UserPrincipalName | Where-Object { $_.Count -gt 1 }

  foreach ($dup in $upnDuplicates) {
    $conflictingDomains = ($dup.Group | Select-Object -ExpandProperty DomainFqdn -Unique) -join '; '
    $conflictingDNs = ($dup.Group | Select-Object -ExpandProperty DistinguishedName) -join ' | '

    $results += [pscustomobject]@{
      ConflictType       = 'UserPrincipalName'
      ConflictValue      = $dup.Name
      ObjectClasses      = 'user'
      ConflictCount      = $dup.Count
      ConflictingDomains = $conflictingDomains
      ConflictingDNs     = $conflictingDNs
      Severity           = 'High'
      Recommendation     = 'Change UPN before migration to prevent authentication issues'
    }
  }

  # Check for duplicate mail attributes (if present)
  $mailDuplicates = $AllUsers | Where-Object { $_.PSObject.Properties['Mail'] -and $_.Mail } |
    Group-Object -Property Mail | Where-Object { $_.Count -gt 1 }

  foreach ($dup in $mailDuplicates) {
    $conflictingDomains = ($dup.Group | Select-Object -ExpandProperty DomainFqdn -Unique) -join '; '
    $conflictingDNs = ($dup.Group | Select-Object -ExpandProperty DistinguishedName) -join ' | '

    $results += [pscustomobject]@{
      ConflictType       = 'Mail'
      ConflictValue      = $dup.Name
      ObjectClasses      = 'user'
      ConflictCount      = $dup.Count
      ConflictingDomains = $conflictingDomains
      ConflictingDNs     = $conflictingDNs
      Severity           = 'Medium'
      Recommendation     = 'Review for Exchange/email conflicts post-migration'
    }
  }

  return $results
}
