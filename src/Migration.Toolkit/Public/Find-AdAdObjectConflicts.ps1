function Find-AdAdObjectConflicts {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateSet('User','Group','Computer')]
    [string]$ObjectType,

    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object[]]$Source,

    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object[]]$Target,

    # Override the default key mapping if your inventories use different property names
    [hashtable]$PropertyMap = @{},   # e.g. @{ Sam='SamAccountName'; Upn='UserPrincipalName'; Dns='DnsHostName'; Name='Name' }

    # When a conflict is found, generate a suggested target SAM like "<sam>_src"
    [string]$RenameSuffix = '_src',

    # If set, return only conflicts; otherwise also returns "NoConflict" rows (useful for auditing)
    [switch]$ConflictsOnly
  )

  function _getProp([object]$o, [string]$propName) {
    if (-not $o) { return $null }
    if ([string]::IsNullOrWhiteSpace($propName)) { return $null }
    $p = $o.PSObject.Properties[$propName]
    if ($null -eq $p) { return $null }
    $v = $p.Value
    if ($null -eq $v) { return $null }
    $s = [string]$v
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    return $s
  }

  # Default property names used by your discovery collectors
  $defaults = @{
    Sam = 'SamAccountName'
    Upn = 'UserPrincipalName'
    Dns = 'DnsHostName'
    Name = 'Name'
    Mail = 'Mail'
  }

  foreach ($k in $PropertyMap.Keys) { $defaults[$k] = $PropertyMap[$k] }

  # Build lookup sets for target
  $targetSam = @{}
  $targetUpn = @{}
  $targetDns = @{}
  $targetName = @{}
  $targetMail = @{}

  foreach ($t in $Target) {
    $sam  = _getProp $t $defaults.Sam
    $upn  = _getProp $t $defaults.Upn
    $dns  = _getProp $t $defaults.Dns
    $name = _getProp $t $defaults.Name
    $mail = _getProp $t $defaults.Mail

    if ($sam)  { $targetSam[$sam.ToLowerInvariant()]  = $t }
    if ($upn)  { $targetUpn[$upn.ToLowerInvariant()]  = $t }
    if ($dns)  { $targetDns[$dns.ToLowerInvariant()]  = $t }
    if ($name) { $targetName[$name.ToLowerInvariant()] = $t }
    if ($mail) { $targetMail[$mail.ToLowerInvariant()] = $t }
  }

  $rows = @()

  foreach ($s in $Source) {
    $sam  = _getProp $s $defaults.Sam
    $upn  = _getProp $s $defaults.Upn
    $dns  = _getProp $s $defaults.Dns
    $name = _getProp $s $defaults.Name
    $mail = _getProp $s $defaults.Mail

    $conflicts = @()
    $with = @()

    if ($sam -and $targetSam.ContainsKey($sam.ToLowerInvariant())) {
      $conflicts += 'SamAccountName'
      $with += (_getProp $targetSam[$sam.ToLowerInvariant()] $defaults.Sam)
    }

    if ($ObjectType -eq 'User') {
      if ($upn -and $targetUpn.ContainsKey($upn.ToLowerInvariant())) {
        $conflicts += 'UserPrincipalName'
        $with += (_getProp $targetUpn[$upn.ToLowerInvariant()] $defaults.Upn)
      }
      if ($mail -and $targetMail.ContainsKey($mail.ToLowerInvariant())) {
        $conflicts += 'Mail'
        $with += (_getProp $targetMail[$mail.ToLowerInvariant()] $defaults.Mail)
      }
    }

    if ($ObjectType -eq 'Computer') {
      if ($dns -and $targetDns.ContainsKey($dns.ToLowerInvariant())) {
        $conflicts += 'DnsHostName'
        $with += (_getProp $targetDns[$dns.ToLowerInvariant()] $defaults.Dns)
      }
      # Optional additional collision on Name
      if ($name -and $targetName.ContainsKey($name.ToLowerInvariant())) {
        $conflicts += 'Name'
        $with += (_getProp $targetName[$name.ToLowerInvariant()] $defaults.Name)
      }
    }

    if ($ObjectType -eq 'Group') {
      # Groups sometimes collide on Name even if sam differs
      if ($name -and $targetName.ContainsKey($name.ToLowerInvariant())) {
        $conflicts += 'Name'
        $with += (_getProp $targetName[$name.ToLowerInvariant()] $defaults.Name)
      }
    }

    $hasConflict = ($conflicts.Count -gt 0)

    if ($ConflictsOnly -and -not $hasConflict) { continue }

    # Recommendation logic
    $recommendation = if (-not $hasConflict) { 'None' } else {
      switch ($ObjectType) {
        'Computer' { 'RenamePostMigrationOrPreStageTargetRename' }
        default    { 'RenameViaIncludeFile' }
      }
    }

    $suggestedTargetSam = $null
    if ($hasConflict -and $sam) {
      $suggestedTargetSam = ($sam + $RenameSuffix)

      # Ensure it doesn't conflict too
      $i = 1
      while ($targetSam.ContainsKey($suggestedTargetSam.ToLowerInvariant())) {
        $suggestedTargetSam = "{0}{1}{2}" -f $sam, $RenameSuffix, $i
        $i++
        if ($i -gt 1000) { break }
      }
    }

    $rows += [pscustomobject]@{
      ObjectType          = $ObjectType
      SourceSamAccountName= $sam
      SourceName          = $name
      SourceUPN           = $upn
      SourceDnsHostName   = $dns
      SourceMail          = $mail

      ConflictKeys        = if ($hasConflict) { ($conflicts | Sort-Object -Unique) -join ';' } else { $null }
      ConflictsWith       = if ($hasConflict) { ($with | Where-Object { $_ } | Sort-Object -Unique) -join ';' } else { $null }

      Recommendation      = $recommendation
      SuggestedTargetSAM  = $suggestedTargetSam
    }
  }

  return @($rows)
}
