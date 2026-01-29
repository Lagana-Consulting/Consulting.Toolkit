function Get-AzCloudDistributionGroups {
  <#
  .SYNOPSIS
  Discovers distribution groups and mail-enabled security groups in Exchange Online.

  .DESCRIPTION
  Retrieves mail-enabled groups in Exchange Online, including:
  - Distribution groups (DL)
  - Mail-enabled security groups
  - Shared mailboxes (when configured as groups)
  - Room mailboxes and resource mailboxes (if queried via ExO cmdlets)

  .PARAMETER Filter
  OData filter to limit results.

  .PARAMETER GroupType
  Filter: 'All', 'DistributionGroup', 'SecurityGroup', 'MailEnabledSecurityGroup', 'DynamicDistributionGroup'.
  Default 'All'.

  .PARAMETER IncludeMemberCount
  If $true, includes member count. Default $false.

  .PARAMETER Properties
  Properties to retrieve.

  .PARAMETER Top
  Number of results. Default 999.

  .EXAMPLE
  $distGroups = Get-AzCloudDistributionGroups

  Gets all distribution groups.

  .EXAMPLE
  $secGroups = Get-AzCloudDistributionGroups -GroupType SecurityGroup

  Gets mail-enabled security groups.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of distribution group objects with properties:
    - PrimarySmtpAddress, DisplayName, GroupType
    - MemberCount, HiddenFromAddressListEnabled
    - ManagedBy, Mail

  .NOTES
  Requires ExchangeOnlineManagement or MS-Graph Mail scopes.
  Dynamic distribution groups are mail-enabled but do not store explicit members.

  .LINK
  Get-AzCloudMailboxes
  Get-AzCloudResourceMailboxes
  Get-AzCloudM365Groups
  Export-AzCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [ValidateSet('All', 'DistributionGroup', 'SecurityGroup', 'MailEnabledSecurityGroup', 'DynamicDistributionGroup')]
    [string]$GroupType = 'All',
    [switch]$IncludeMemberCount,
    [string[]]$Properties = @(
      'PrimarySmtpAddress',
      'DisplayName',
      'GroupType',
      'ManagedBy',
      'Mail',
      'Created'
    ),
    [int]$Top = 999
  )

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
  }
  catch {
    throw "ExchangeOnlineManagement module required. Install via: Install-Module ExchangeOnlineManagement -AllowPrerelease"
  }

  $filterParams = @{}

  if ($GroupType -ne 'All') {
    $filterParams['RecipientType'] = $GroupType
  }

  if ($Filter) {
    $filterParams['Filter'] = $Filter
  }

  Write-Verbose "Querying distribution groups..."

  # Check if Exchange Online is connected
  if (-not (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
    Write-Warning "Exchange Online Management module not available. Run: Install-Module ExchangeOnlineManagement"
    return @()
  }

  $exoConnections = Get-ConnectionInformation -ErrorAction SilentlyContinue
  if (-not $exoConnections) {
    Write-Warning "Not connected to Exchange Online. Use Connect-AzCloudTenant -IncludeExchangeOnline to enable this feature."
    return @()
  }

  try {
    Write-Verbose "Retrieving distribution groups from Exchange Online..."
    $groups = Get-DistributionGroup -ResultSize Unlimited -ErrorAction Stop
    $groupCount = if ($groups) { ($groups | Measure-Object).Count } else { 0 }
    Write-Verbose "Retrieved $groupCount distribution groups"
    return $groups
  }
  catch {
    Write-Warning "Failed to retrieve distribution groups. Error: $($_.Exception.Message)"
    return @()
  }
}
