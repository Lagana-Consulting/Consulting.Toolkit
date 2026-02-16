function Get-AzCloudUsers {
  <#
  .SYNOPSIS
  Discovers all users in the connected Entra ID tenant.

  .DESCRIPTION
  Queries MS-Graph /users endpoint and retrieves comprehensive user information including:
  - Identity attributes (ID, UPN, DisplayName, Mail)
  - Account state (AccountEnabled, CreatedDateTime, LastPasswordChangeDateTime)
  - License and sign-in status
  - Risk indicators (Sign-in risk, User risk)

  Results can be filtered by account state or export to CSV.

  .PARAMETER Filter
  OData filter to limit results. Examples:
    - "accountEnabled eq true" - Only enabled users
    - "userType eq 'Member'" - Members only (excludes guests)
    - "createdDateTime ge 2023-01-01T00:00:00Z" - Created after date

  .PARAMETER Properties
  Specific properties to retrieve. Default includes all common discovery properties.
  For minimal/fast queries, specify subset: @('id', 'userPrincipalName', 'displayName', 'mail')

  .PARAMETER Top
  Number of results to return. Default 999. API has 999 limit per call; paging is automatic.

  .PARAMETER IncludeGuests
  If $true, includes guest users (B2B). Default includes all user types.

  .PARAMETER IncludeRiskData
  If $true, includes risk indicators (Sign-in risk, User risk). Requires additional Graph permissions.
  Default $false for performance.

  .PARAMETER IncludeLicenseInfo
  If $true, includes detailed license SKU info. Requires assignedLicenses expansion.
  Default $false for performance.

  .EXAMPLE
  $users = Get-AzCloudUsers

  Gets all users in tenant with default properties.

  .EXAMPLE
  $activeUsers = Get-AzCloudUsers -Filter "accountEnabled eq true"

  Gets only enabled users.

  .EXAMPLE
  $members = Get-AzCloudUsers -IncludeGuests $false

  Gets only member users (excludes B2B guests).

  .EXAMPLE
  $guestUsers = Get-AzCloudUsers -Filter "userType eq 'Guest'"

  Gets only guest accounts.

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  [PSObject] Array of user objects with properties:
    - id, userPrincipalName, displayName, mail, givenName, surname
    - accountEnabled, createdDateTime, lastPasswordChangeDateTime
    - userType, licenseAssignmentStates
    - signInActivity (lastSignInDateTime, lastNonInteractiveSignInDateTime)
    - Optional: riskState, riskLevel, userRiskLevel

  .NOTES
  Requires Graph scope: User.Read.All
  Large tenant discovery (100k+ users) may require batching; use Filter to scope query.
  Risk data requires additional premium scopes; may be empty if not licensed.

  .LINK
  Get-AzCloudGroups
  Get-AzCloudDevices
  Export-AzCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [string[]]$Properties = @(
      'id',
      'userPrincipalName',
      'displayName',
      'mail',
      'givenName',
      'surname',
      'accountEnabled',
      'createdDateTime',
      'lastPasswordChangeDateTime',
      'userType',
      'mailNickname',
      'proxyAddresses',
      'objectType',
      'licenseAssignmentStates',
      'onPremisesSyncEnabled'
    ),
    [int]$Top = 999,
    [switch]$IncludeGuests,
    [switch]$IncludeRiskData,
    [switch]$IncludeLicenseInfo
  )

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  # Validate module is available (may already be loaded from Connect)
  $usersModule = Get-Module Microsoft.Graph.Users -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $usersModule) {
    throw "Microsoft.Graph.Users module not installed. Run: .\Install-CloudDiscoveryPrerequisites.ps1"
  }

  # Try to load if not already loaded
  try {
    if (-not (Get-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue)) {
      Import-Module Microsoft.Graph.Users -ErrorAction Stop -SkipEditionCheck
    }
  }
  catch {
    Write-Warning "Could not import Microsoft.Graph.Users module (may already be loaded). Proceeding..."
  }

  $params = @{
    All         = $true
    ErrorAction = 'Stop'
  }

  if ($Filter) {
    # Add guest filter if not explicitly including guests
    if (-not $IncludeGuests) {
      $Filter = "$Filter and userType eq 'Member'"
    }
    $params['Filter'] = $Filter
  }
  elseif (-not $IncludeGuests) {
    $params['Filter'] = "userType eq 'Member'"
  }

  # Add risk properties if requested
  if ($IncludeRiskData) {
    $Properties += @('riskState', 'riskLevel', 'userRiskLevel')
  }

  if ($IncludeLicenseInfo) {
    $Properties += 'assignedLicenses'
  }

  # Select properties
  $params['Property'] = $Properties

  Write-Verbose "Querying users with filter: $($params['Filter'] -or 'none')"

  try {
    $users = Get-MgUser @params
    Write-Verbose "Retrieved $($users.Count) users"
    return $users
  }
  catch {
    throw "Failed to retrieve users from MS-Graph. $($_.Exception.Message)"
  }
}
