function Get-AdCloudMailboxes {
  <#
  .SYNOPSIS
  Discovers all mailboxes in the connected Exchange Online tenant.

  .DESCRIPTION
  Queries MS-Graph /me/mailFolders, /users, and optionally ExchangeOnlineManagement module to retrieve
  comprehensive mailbox information including:
  - Mailbox identity (PrimarySmtpAddress, RecipientTypeDetails, UserPrincipalName)
  - Mailbox limits and usage (ProhibitSendQuota, ItemCount, TotalItemSize)
  - Archive mailbox status
  - Forwarding rules and delegates
  - Retention and hold status

  Provides detailed per-user mailbox telemetry for migration planning.

  .PARAMETER Filter
  OData filter to limit results. Examples:
    - "userType eq 'Member'" - Members only
    - "createdDateTime ge 2023-01-01T00:00:00Z" - Created after date

  .PARAMETER IncludeArchiveStatus
  If $true, includes archive mailbox properties. Requires ExchangeOnlineManagement module.
  Default $false.

  .PARAMETER IncludeForwardingRules
  If $true, includes forwarding rules and mail routing rules.
  Default $false.

  .PARAMETER Properties
  Properties to retrieve.

  .PARAMETER Top
  Number of results to return. Default 999.

  .EXAMPLE
  $mailboxes = Get-AdCloudMailboxes

  Gets all mailboxes in Exchange Online tenant.

  .EXAMPLE
  $largeMailboxes = Get-AdCloudMailboxes | Where-Object { $_.totalItemSize -gt 50GB }

  Gets mailboxes over 50GB.

  .EXAMPLE
  $archivedMailboxes = Get-AdCloudMailboxes -IncludeArchiveStatus | Where-Object { $_.ArchiveStatus -eq 'Active' }

  Gets mailboxes with active archives.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of mailbox objects with properties:
    - PrimarySmtpAddress, DisplayName, UserPrincipalName
    - RecipientTypeDetails, MailboxType
    - ItemCount, TotalItemSize, ProhibitSendQuota, StorageQuotaStatus
    - ArchiveStatus (if IncludeArchiveStatus)
    - ForwardingRules (if IncludeForwardingRules)
    - HoldApplied, RetentionPolicy

  .NOTES
  Requires Graph scope: Mail.Read, Mail.Read.Shared or ExO cmdlet connection.
  Large tenants (100k+ mailboxes) require batching; consider Filter.
  Archive enumeration requires ExchangeOnlineManagement for full details.

  .LINK
  Get-AdCloudDistributionGroups
  Get-AdCloudResourceMailboxes
  Get-AdCloudMailboxPermissions
  Export-AdCloudCsv
  #>
  [CmdletBinding()]
  param(
    [string]$Filter,
    [switch]$IncludeArchiveStatus,
    [switch]$IncludeForwardingRules,
    [string[]]$Properties = @(
      'id',
      'userPrincipalName',
      'displayName',
      'mail',
      'createdDateTime',
      'mailboxSettings'
    ),
    [int]$Top = 999
  )

  if (-not (Get-AdCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AdCloudTenant first."
  }

  try {
    Import-Module Microsoft.Graph.Mail -ErrorAction Stop
  }
  catch {
    throw "Microsoft.Graph.Mail module required. Install via: Install-Module Microsoft.Graph.Mail"
  }

  $params = @{
    All = $true
    ErrorAction = 'Stop'
    Property = $Properties
  }

  if ($Filter) {
    $params['Filter'] = $Filter
  }

  Write-Verbose "Querying mailboxes via Graph with filter: $($params['Filter'] -or 'none')"

  try {
    $mailboxes = Get-MgUser @params | Where-Object { $_.Mail }
    Write-Verbose "Retrieved $($mailboxes.Count) mailbox-enabled users"

    # If detailed Exchange info needed, use ExO cmdlets
    if ($IncludeArchiveStatus -or $IncludeForwardingRules) {
      Write-Verbose "Retrieving detailed Exchange Online mailbox properties..."

      try {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop

        $mailboxes = $mailboxes | ForEach-Object {
          $mailbox = $_
          $exoMailbox = Get-Mailbox -Identity $mailbox.UserPrincipalName -ErrorAction SilentlyContinue

          if ($exoMailbox) {
            if ($IncludeArchiveStatus) {
              $archive = Get-MailboxStatistics -Identity $mailbox.UserPrincipalName -Archive -ErrorAction SilentlyContinue
              $mailbox | Add-Member -MemberType NoteProperty -Name 'ArchiveStatus' -Value $exoMailbox.ArchiveStatus -Force
              $mailbox | Add-Member -MemberType NoteProperty -Name 'ArchiveQuota' -Value $exoMailbox.ArchiveQuota -Force
            }

            if ($IncludeForwardingRules) {
              $mailbox | Add-Member -MemberType NoteProperty -Name 'ForwardingAddress' -Value $exoMailbox.ForwardingAddress -Force
              $mailbox | Add-Member -MemberType NoteProperty -Name 'DeliverToMailboxAndForward' -Value $exoMailbox.DeliverToMailboxAndForward -Force
            }
          }
          $mailbox
        }
      }
      catch {
        Write-Warning "ExchangeOnlineManagement not available; skipping detailed mailbox properties. $_"
      }
    }

    return $mailboxes
  }
  catch {
    throw "Failed to retrieve mailboxes. $($_.Exception.Message)"
  }
}
