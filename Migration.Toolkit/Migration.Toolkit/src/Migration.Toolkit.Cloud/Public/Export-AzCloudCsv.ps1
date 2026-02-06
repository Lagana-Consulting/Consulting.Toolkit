function Export-AzCloudCsv {
  <#
  .SYNOPSIS
  Exports cloud discovery data to CSV with enforced schema consistency.

  .DESCRIPTION
  Wrapper around Export-Csv that enforces consistent column ordering and handles
  complex object serialization for CSV export.

  .PARAMETER InputObject
  Objects to export. Accepts pipeline input.

  .PARAMETER Path
  CSV file path.

  .PARAMETER SchemaName
  Optional schema name (for future schema enforcement; reserved for expansion).

  .PARAMETER Encoding
  File encoding. Default UTF8.

  .PARAMETER NoClobber
  If $true, does not overwrite existing file.

  .EXAMPLE
  $users | Export-AzCloudCsv -Path "users.csv"

  Exports users to CSV with consistent schema.

  .INPUTS
  [PSObject] via pipeline.

  .OUTPUTS
  None; writes to file.

  .NOTES
  Automatically flattens nested properties for CSV compatibility.

  .LINK
  Get-AzCloudUsers
  Get-AzCloudGroups
  Invoke-AzCloudDiscovery
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [PSObject]$InputObject,

    [Parameter(Mandatory)]
    [string]$Path,

    [string]$SchemaName,

    [ValidateSet('UTF8', 'UTF8NoBOM', 'ASCII', 'Default')]
    [string]$Encoding = 'UTF8',

    [switch]$NoClobber
  )

  begin {
    $collection = @()
  }

  process {
    $collection += $InputObject
  }

  end {
    if ($collection.Count -eq 0) {
      Write-Verbose "No objects to export to $Path"
      return
    }

    $csvParams = @{
      Path              = $Path
      Encoding          = $Encoding
      NoTypeInformation = $true
      ErrorAction       = 'Stop'
    }

    if ($NoClobber) {
      $csvParams['NoClobber'] = $true
    }

    try {
      # Select only simple properties (exclude complex Graph objects)
      $simplified = $collection | Select-Object -Property * -ExcludeProperty @(
        # Exclude complex navigation properties that appear as type names
        'Activities', 'AgreementAcceptances', 'AppRoleAssignments', 'AssignedLicenses', 'AssignedPlans',
        'Authentication', 'AuthorizationInfo', 'Calendar', 'CalendarGroups', 'CalendarView', 'Calendars',
        'Chats', 'CloudClipboard', 'ContactFolders', 'Contacts', 'CreatedObjects', 'CustomSecurityAttributes',
        'DataSecurityAndGovernance', 'DeviceManagementTroubleshootingEvents', 'DirectReports', 'Drive', 'Drives',
        'EmployeeExperience', 'EmployeeOrgData', 'Events', 'Extensions', 'FollowedSites', 'Identities',
        'InferenceClassification', 'Insights', 'JoinedTeams', 'LicenseAssignmentStates', 'LicenseDetails',
        'MailFolders', 'MailboxSettings', 'ManagedAppRegistrations', 'ManagedDevices', 'Manager', 'MemberOf',
        'Messages', 'Oauth2PermissionGrants', 'OnPremisesExtensionAttributes', 'OnPremisesProvisioningErrors',
        'Onenote', 'OnlineMeetings', 'Outlook', 'OwnedDevices', 'OwnedObjects', 'PasswordProfile',
        'People', 'PermissionGrants', 'Photo', 'Photos', 'Planner', 'Presence', 'Print', 'ProvisionedPlans',
        'RegisteredDevices', 'ScopedRoleMemberOf', 'ServiceProvisioningErrors', 'Settings', 'SignInActivity',
        'Solutions', 'Sponsors', 'Teamwork', 'Todo', 'TransitiveMemberOf', 'AdditionalProperties',
        # Group-specific complex properties
        'Members', 'Owners', 'Sites', 'Drives', 'Threads', 'Conversations',
        # Application-specific complex properties
        'AppRoles', 'KeyCredentials', 'PasswordCredentials', 'PublisherDomain',
        # Team-specific complex properties
        'Channels', 'InstalledApps', 'Operations', 'Schedule', 'Template',
        # Device-specific complex properties
        'Commands', 'Extensions', 'HostedDevices', 'MemberOf', 'RegisteredOwners', 'RegisteredUsers'
      )

      # Flatten remaining properties for CSV
      $flattened = $simplified | ForEach-Object {
        $obj = $_
        $flatObj = [PSCustomObject]@{}

        foreach ($prop in $obj.PSObject.Properties) {
          $value = $prop.Value

          # Skip null or complex objects
          if ($null -eq $value) {
            $flatValue = ''
          }
          # Convert arrays to semicolon-separated strings
          elseif ($value -is [array]) {
            $flatValue = ($value | Where-Object { $_ -and $_ -notmatch '^Microsoft\.Graph' } | ForEach-Object { $_.ToString() }) -join '; '
          }
          # Convert dictionaries to JSON
          elseif ($value -is [System.Collections.IDictionary]) {
            $flatValue = ($value | ConvertTo-Json -Compress -Depth 1)
          }
          # Skip complex Graph objects that slipped through
          elseif ($value.ToString() -match '^Microsoft\.Graph\.PowerShell\.Models\.') {
            $flatValue = ''
          }
          # Use simple value
          else {
            $flatValue = $value.ToString()
          }

          # Only add if there's actual data
          if ($flatValue -ne '') {
            $flatObj | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $flatValue -Force
          }
        }

        $flatObj
      }

      $flattened | Export-Csv @csvParams
      Write-Verbose "Exported $($collection.Count) records to $Path"
    }
    catch {
      throw "Failed to export CSV to $Path. $($_.Exception.Message)"
    }
  }
}
