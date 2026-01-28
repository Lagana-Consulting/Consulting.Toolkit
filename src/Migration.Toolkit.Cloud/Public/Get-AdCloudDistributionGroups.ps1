function Get-AdCloudDistributionGroups {
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
  $distGroups = Get-AdCloudDistributionGroups

  Gets all distribution groups.

  .EXAMPLE
  $secGroups = Get-AdCloudDistributionGroups -GroupType SecurityGroup

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
  Get-AdCloudMailboxes
  Get-AdCloudResourceMailboxes
  Get-AdCloudM365Groups
  Export-AdCloudCsv
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

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
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

  Write-Verbose "Querying distribution groups with type filter: $GroupType"

  try {
    $distGroups = Get-DistributionGroup @filterParams -ResultSize $Top -ErrorAction Stop

    if ($IncludeMemberCount) {
      Write-Verbose "Retrieving member counts for $($distGroups.Count) groups..."
      $distGroups = $distGroups | ForEach-Object {
        $memberCount = (Get-DistributionGroupMember -Identity $_.Identity -ResultSize $Top -ErrorAction SilentlyContinue | Measure-Object).Count
        $_ | Add-Member -MemberType NoteProperty -Name 'MemberCount' -Value $memberCount -Force
        $_
      }
    }

    Write-Verbose "Retrieved $($distGroups.Count) distribution groups"
    return $distGroups
  }
  catch {
    throw "Failed to retrieve distribution groups. $($_.Exception.Message)"
  }
}
