function Test-AdAdmtTrustPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDomain,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetDomain,

    # Optional: specify a DC to query (useful in locked-down environments)
    [string]$Server,

    [switch]$ThrowOnFailure
  )

  if (-not (Get-Command Get-ADTrust -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD DS tools."
  }

  $messages = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]

  # Query trust from source domain perspective
  $trustParams = @{
    Filter = "Target -eq '$TargetDomain'"
    ErrorAction = 'Stop'
  }
  if ($Server) { $trustParams['Server'] = $Server }

  $trust = $null
  try {
    $trust = Get-ADTrust @trustParams
  } catch {
    $messages.Add("Failed to query trust from $SourceDomain to $TargetDomain`: $($_.Exception.Message)")
  }

  $trustExists = [bool]$trust
  if (-not $trustExists) {
    $messages.Add("No trust relationship found from $SourceDomain to $TargetDomain")
  }

  # Check trust direction (need at least Inbound to target for ADMT)
  $directionValid = $false
  $trustDirection = $null
  if ($trust) {
    $trustDirection = $trust.Direction
    # Direction values: Inbound (1), Outbound (2), Bidirectional (3)
    # For ADMT: Source needs Outbound to Target (value 2 or 3)
    $directionValid = $trustDirection -in @('Outbound', 'Bidirectional', 2, 3)

    if (-not $directionValid) {
      $messages.Add("Trust direction is '$trustDirection' - ADMT requires Outbound or Bidirectional from source")
    }
  }

  # Check SID filtering status (SID History migration requires SID Filtering to be disabled)
  $sidFilteringQuarantined = $false
  $sidHistoryEnabled = $false
  if ($trust) {
    # SIDFilteringQuarantined = $true means SID filtering is ENABLED (blocks SID History)
    # SIDFilteringForestAware also affects this but is less common
    if ($trust.PSObject.Properties['SIDFilteringQuarantined']) {
      $sidFilteringQuarantined = [bool]$trust.SIDFilteringQuarantined
    }

    $sidHistoryEnabled = -not $sidFilteringQuarantined

    if ($sidFilteringQuarantined) {
      $warnings.Add("SID Filtering is enabled (quarantine mode). SID History migration will fail unless disabled with: netdom trust $SourceDomain /domain:$TargetDomain /quarantine:no")
    }
  }

  # Check trust type (External vs. Forest)
  $trustType = if ($trust -and $trust.PSObject.Properties['TrustType']) {
    $trust.TrustType
  } else {
    $null
  }

  # Forest trusts are preferred for ADMT (more features)
  if ($trustType -and $trustType -notmatch 'Forest|2') {
    $warnings.Add("Trust type is '$trustType' - Forest trusts are recommended for full ADMT functionality")
  }

  $passed = $trustExists -and $directionValid

  $result = [pscustomobject]@{
    SourceDomain              = $SourceDomain
    TargetDomain              = $TargetDomain
    TrustExists               = $trustExists
    TrustDirection            = $trustDirection
    DirectionValid            = $directionValid
    TrustType                 = $trustType
    SIDFilteringQuarantined   = $sidFilteringQuarantined
    SIDHistoryEnabled         = $sidHistoryEnabled
    Messages                  = $messages.ToArray()
    Warnings                  = $warnings.ToArray()
    Passed                    = $passed
    TrustObject               = $trust
  }

  if ($ThrowOnFailure -and -not $passed) {
    $detail = if ($messages.Count -gt 0) { $messages -join '; ' } else { 'Unknown failure' }
    throw "ADMT trust validation failed. $detail"
  }

  return $result
}
