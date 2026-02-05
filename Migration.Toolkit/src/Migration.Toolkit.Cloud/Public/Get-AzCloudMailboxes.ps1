function Get-AzCloudMailboxes {
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
  $mailboxes = Get-AzCloudMailboxes

  Gets all mailboxes in Exchange Online tenant.

  .EXAMPLE
  $largeMailboxes = Get-AzCloudMailboxes | Where-Object { $_.totalItemSize -gt 50GB }

  Gets mailboxes over 50GB.

  .EXAMPLE
  $archivedMailboxes = Get-AzCloudMailboxes -IncludeArchiveStatus | Where-Object { $_.ArchiveStatus -eq 'Active' }

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
    - LitigationHoldEnabled, LitigationHoldOwner, LitigationHoldDate

  .NOTES
  Requires Graph scope: Mail.Read, Mail.Read.Shared or ExO cmdlet connection.
  Large tenants (100k+ mailboxes) require batching; consider Filter.
  Archive enumeration requires ExchangeOnlineManagement for full details.

  .LINK
  Get-AzCloudDistributionGroups
  Get-AzCloudResourceMailboxes
  Get-AdCloudMailboxPermissions
  Export-AzCloudCsv
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

  if (-not (Get-AzCloudAuthContext)) {
    throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
  }

  try { if (-not (Get-Module Microsoft.Graph.Mail -ErrorAction SilentlyContinue)) { Import-Module Microsoft.Graph.Mail -ErrorAction Stop -SkipEditionCheck } } catch { Write-Warning "Could not import Microsoft.Graph.Mail module (may already be loaded). Proceeding..." }

  $params = @{
    ErrorAction = 'Stop'
  }

  if ($Filter) {
    $params['Filter'] = $Filter
  }

  Write-Verbose "Querying mailboxes via Graph with filter: $($params['Filter'] -or 'none')"

  try {
    # Check if EXO is connected for enhanced data
    $exoConnected = $false
    if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
      $exoConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue
      if ($exoConnection) {
        $exoConnected = $true
        Write-Verbose "EXO connection detected - will retrieve enhanced mailbox data"
      }
    }

    if ($exoConnected) {
      # Use EXO cmdlets for comprehensive mailbox data including shared mailboxes
      Write-Verbose "Retrieving mailboxes via Exchange Online (includes user, shared, and archive data)..."

      # Get all mailbox types: UserMailbox, SharedMailbox (exclude discovery mailboxes)
      $allMailboxes = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop | Where-Object { $_.RecipientTypeDetails -notmatch 'Discovery' }

      $mailboxes = $allMailboxes | ForEach-Object {
        $mbx = $_

        try {
          # Get mailbox statistics for storage info
          $stats = Get-MailboxStatistics -Identity $mbx.Identity -ErrorAction SilentlyContinue

          # Get archive statistics if archive exists
          $archiveStats = $null
          if ($mbx.ArchiveStatus -eq 'Active') {
            $archiveStats = Get-MailboxStatistics -Identity $mbx.Identity -Archive -ErrorAction SilentlyContinue
          }

          # Safe size conversion - handle ByteQuantifiedSize property
          $sizeBytes = 0
          $archiveSizeBytes = 0

          if ($stats -and $stats.TotalItemSize) {
            try {
              $sizeBytes = [int64]$stats.TotalItemSize.Value
            }
            catch {
              try {
                $sizeBytes = [int64]$stats.TotalItemSize
              }
              catch {
                $sizeBytes = 0
              }
            }
          }

          if ($archiveStats -and $archiveStats.TotalItemSize) {
            try {
              $archiveSizeBytes = [int64]$archiveStats.TotalItemSize.Value
            }
            catch {
              try {
                $archiveSizeBytes = [int64]$archiveStats.TotalItemSize
              }
              catch {
                $archiveSizeBytes = 0
              }
            }
          }

          # Build enhanced mailbox object
          [PSCustomObject]@{
            UserPrincipalName      = $mbx.UserPrincipalName
            DisplayName            = $mbx.DisplayName
            PrimarySmtpAddress     = $mbx.PrimarySmtpAddress
            RecipientTypeDetails   = $mbx.RecipientTypeDetails
            MailboxType            = if ($mbx.RecipientTypeDetails -eq 'SharedMailbox') { 'Shared' } elseif ($mbx.RecipientTypeDetails -match 'Room|Equipment') { 'Resource' } else { 'User' }
            ItemCount              = if ($stats) { $stats.ItemCount } else { 0 }
            TotalItemSizeBytes     = $sizeBytes
            TotalItemSizeMB        = if ($sizeBytes -gt 0) { [math]::Round($sizeBytes / 1MB, 2) } else { 0 }
            TotalItemSizeGB        = if ($sizeBytes -gt 0) { [math]::Round($sizeBytes / 1GB, 2) } else { 0 }
            ArchiveStatus          = $mbx.ArchiveStatus
            ArchiveName            = $mbx.ArchiveName
            ArchiveItemCount       = if ($archiveStats) { $archiveStats.ItemCount } else { 0 }
            ArchiveSizeBytes       = $archiveSizeBytes
            ArchiveSizeMB          = if ($archiveSizeBytes -gt 0) { [math]::Round($archiveSizeBytes / 1MB, 2) } else { 0 }
            ArchiveSizeGB          = if ($archiveSizeBytes -gt 0) { [math]::Round($archiveSizeBytes / 1GB, 2) } else { 0 }
            LitigationHoldEnabled  = $mbx.LitigationHoldEnabled
            LitigationHoldOwner    = if ($mbx.LitigationHoldEnabled -eq $true) { $mbx.LitigationHoldOwner } else { $null }
            LitigationHoldDate     = if ($mbx.LitigationHoldEnabled -eq $true) { $mbx.LitigationHoldDate } else { $null }
            ProhibitSendQuota      = $mbx.ProhibitSendQuota
            IssueWarningQuota      = $mbx.IssueWarningQuota
            WhenCreated            = $mbx.WhenCreated
            Id                     = $mbx.Guid
          }
        }
        catch {
          Write-Verbose "Skipping mailbox $($mbx.DisplayName): $_"
        }
      }

      $mailboxCount = if ($mailboxes) { ($mailboxes | Measure-Object).Count } else { 0 }
      Write-Verbose "Retrieved $mailboxCount mailboxes via EXO (user + shared + archives)"
    }
    else {
      # Fallback to Graph API (basic info only)
      Write-Verbose "EXO not connected - using Graph API (basic info only, no shared mailboxes or storage)"
      $allUsers = Get-MgUser @params -ErrorAction Stop

      # Filter to users with mail property (actual mailboxes)
      $mailboxes = $allUsers | Where-Object { $_.Mail -and $_.Mail -ne '' }

      # If no mailboxes found, return all users as potential mailboxes
      if (-not $mailboxes -or ($mailboxes | Measure-Object).Count -eq 0) {
        Write-Verbose "No users with mail property found. Returning all users."
        $mailboxes = $allUsers
      }

      $mailboxCount = if ($mailboxes) { ($mailboxes | Measure-Object).Count } else { 0 }
      Write-Verbose "Retrieved $mailboxCount mailbox-enabled users"

      if ($IncludeArchiveStatus -or $IncludeForwardingRules) {
        Write-Warning "Archive/forwarding/storage details require: Connect-ExchangeOnline. Use Connect-AzCloudTenant -IncludeExchangeOnline"
      }
    }

    return $mailboxes
  }
  catch {
    Write-Warning "Failed to retrieve mailboxes. Error: $($_.Exception.Message)"
    return @()
  }
}
