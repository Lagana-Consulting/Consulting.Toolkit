function Get-AdCloudResourceMailboxes {
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
  $rooms = Get-AdCloudResourceMailboxes -ResourceType Room

  Gets all room mailboxes.

  .EXAMPLE
  $resources = Get-AdCloudResourceMailboxes -IncludeBookingPolicy

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
  Get-AdCloudMailboxes
  Get-AdCloudDistributionGroups
  Export-AdCloudCsv
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

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
  }
  catch {
    throw "ExchangeOnlineManagement module required."
  }

  Write-Verbose "Querying resource mailboxes with type filter: $ResourceType"

  try {
    $recipientFilter = "RecipientTypeDetails -eq '$ResourceType'" -replace "All", "Room -or RecipientTypeDetails -eq Equipment"

    $resources = Get-Mailbox -Filter $recipientFilter -ResultSize $Top -ErrorAction Stop

    if ($IncludeBookingPolicy) {
      Write-Verbose "Retrieving booking policies for $($resources.Count) resources..."
      $resources = $resources | ForEach-Object {
        $bookingPolicy = Get-CalendarProcessing -Identity $_.Identity -ErrorAction SilentlyContinue
        $_ | Add-Member -MemberType NoteProperty -Name 'BookingDelegates' -Value $bookingPolicy.BookingDelegateUsers -Force
        $_ | Add-Member -MemberType NoteProperty -Name 'BookingInspectorEnabled' -Value $bookingPolicy.BookingInspectorEnabled -Force
        $_
      }
    }

    Write-Verbose "Retrieved $($resources.Count) resource mailboxes"
    return $resources
  }
  catch {
    throw "Failed to retrieve resource mailboxes. $($_.Exception.Message)"
  }
}
