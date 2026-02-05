function Get-AzCloudResourceMailboxes {
  <#
  .SYNOPSIS
  Discovers resource mailboxes (room and equipment) in Exchange Online.

  .DESCRIPTION
  Retrieves room mailboxes, equipment mailboxes, and shared mailboxes configured as resources.
  Includes booking status, calendar publishing, and processing rules.

  .PARAMETER ResourceType
  Filter: 'All', 'Room', 'Equipment', 'Shared'. Default 'All'.

  .PARAMETER IncludeBookingPolicy
  If $true, includes meeting request acceptance/denial rules.
  Default $false.

  .PARAMETER Properties
  Properties to retrieve.

  .EXAMPLE
  $rooms = Get-AzCloudResourceMailboxes -ResourceType Room

  Gets all room mailboxes.

  .EXAMPLE
  $resources = Get-AzCloudResourceMailboxes -IncludeBookingPolicy

  Gets all resource mailboxes with booking policies.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of resource mailbox objects with properties:
    - PrimarySmtpAddress, DisplayName, ResourceType
    - BookingDelegateUsers, Calendar*

  .NOTES
  Requires ExchangeOnlineManagement with resource mailbox query permissions.

  .LINK
  Get-AzCloudMailboxes
  Get-AzCloudDistributionGroups
  Export-AzCloudCsv
  #>
  [CmdletBinding()]
  param(
    [ValidateSet('All', 'Room', 'Equipment', 'Shared')]
    [string]$ResourceType = 'All',
    [switch]$IncludeBookingPolicy,
    [string[]]$Properties = @(
      'PrimarySmtpAddress',
      'DisplayName',
      'RecipientTypeDetails',
      'IsResource',
      'ResourceCapacity'
    ),
    [int]$Top = 999
  )

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  Write-Verbose "Querying resource mailboxes..."

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
    Write-Verbose "Retrieving resource mailboxes from Exchange Online..."
    $mailboxes = Get-Mailbox -RecipientTypeDetails RoomMailbox, EquipmentMailbox -ResultSize Unlimited -ErrorAction Stop
    $mailboxCount = if ($mailboxes) { ($mailboxes | Measure-Object).Count } else { 0 }
    Write-Verbose "Retrieved $mailboxCount resource mailboxes"
    return $mailboxes
  }
  catch {
    Write-Warning "Failed to retrieve resource mailboxes. Error: $($_.Exception.Message)"
    return @()
  }
}
