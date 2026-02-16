function Get-AzCloudSensitivityLabels {
    <#
  .SYNOPSIS
  Retrieves Microsoft Purview Sensitivity Labels from the connected tenant.

  .DESCRIPTION
  Queries Microsoft Graph beta endpoints to retrieve:
  - Sensitivity label definitions (organization labels available for use)
  - Sensitivity labels applied to SharePoint sites
  - Sensitivity labels applied to M365 Groups
  - Label policies and configurations (retention, encryption, marking rules)

  Provides data governance and sensitivity labeling audit for migration planning.

  .PARAMETER IncludeLabels
  If $true, retrieves all available sensitivity label definitions.
  Default $true.

  .PARAMETER IncludeAppliedLabels
  If $true, retrieves labels applied to sites and groups.
  Default $true.

  .PARAMETER IncludeLabelPolicies
  If $true, retrieves label policies and enforcement settings.
  Default $false (beta, may require additional permissions).

  .EXAMPLE
  $labels = Get-AzCloudSensitivityLabels

  Gets all available sensitivity labels and their current applications.

  .EXAMPLE
  $labeledSites = Get-AzCloudSensitivityLabels -IncludeLabelPolicies | Where-Object { $_.Type -eq 'Site' }

  Gets all sensitivity labels applied to SharePoint sites.

  .INPUTS
  None.

  .OUTPUTS
  [PSObject] Array of sensitivity label objects with properties:
    - Name, Id, Description
    - LabelType (Label Definition, Applied to Site, Applied to Group)
    - AppliedTo (resource name/URL)
    - CreatedDateTime, LastModifiedDateTime
    - IsActive
    - EncryptionEnabled, RetentionEnabled, MarkingsEnabled
    - ParentId (for sublabels)

  .NOTES
  Requires Graph scope: InformationProtection.Read.All or higher
  Uses beta endpoints: /security/informationProtection/sensitivityLabels
  Relies on Connect-AzCloudTenant being called first.

  .LINK
  Get-AzCloudSharePointSites
  Get-AzCloudM365Groups
  Invoke-MgGraphRequest
  #>
    [CmdletBinding()]
    param(
        [switch]$IncludeLabels = $true,
        [switch]$IncludeAppliedLabels = $true,
        [switch]$IncludeLabelPolicies = $false
    )

    if (-not (Get-AzCloudAuthContext)) {
        throw "Not connected to cloud tenant. Call Connect-AzCloudTenant first."
    }

    $results = @()

    try {
        Write-Verbose "Gathering sensitivity labels from Microsoft Purview..."

        # Retrieve available sensitivity label definitions
        if ($IncludeLabels) {
            Write-Verbose "Retrieving sensitivity label definitions..."

            try {
                $labelUri = "https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels"
                $labelResponse = Invoke-MgGraphRequest -Method GET -Uri $labelUri -ErrorAction Stop

                if ($labelResponse.value) {
                    $labelResponse.value | ForEach-Object {
                        $results += [PSCustomObject]@{
                            Name                 = $_.displayName
                            Id                   = $_.id
                            Description          = $_.description
                            LabelType            = 'Definition'
                            AppliedTo            = 'Organization-wide'
                            IsActive             = $true
                            EncryptionEnabled    = if ($_.labelActions) { $_.labelActions | Where-Object { $_.type -eq 'encrypt' } | Measure-Object | Select-Object -ExpandProperty Count -gt 0 } else { $false }
                            RetentionEnabled     = if ($_.labelActions) { $_.labelActions | Where-Object { $_.type -eq 'retentionAction' } | Measure-Object | Select-Object -ExpandProperty Count -gt 0 } else { $false }
                            MarkingsEnabled      = if ($_.labelActions) { $_.labelActions | Where-Object { $_.type -eq 'addContentFooter' -or $_.type -eq 'addContentHeader' -or $_.type -eq 'addWatermark' } | Measure-Object | Select-Object -ExpandProperty Count -gt 0 } else { $false }
                            ParentId             = $_.parent.id
                            CreatedDateTime      = $_.createdDateTime
                            LastModifiedDateTime = $_.lastModifiedDateTime
                            Priority             = $_.priority
                            Tooltip              = $_.tooltip
                            Color                = $_.color
                        }
                    }
                    Write-Verbose "Retrieved $($labelResponse.value.Count) sensitivity label definitions"
                }
            }
            catch {
                Write-Warning "Could not retrieve sensitivity labels: $_"
            }
        }

        # Retrieve labels applied to SharePoint sites
        if ($IncludeAppliedLabels) {
            Write-Verbose "Retrieving sensitivity labels applied to SharePoint sites..."

            try {
                $siteUri = "https://graph.microsoft.com/v1.0/sites?`$select=id,displayName,webUrl"
                $siteResponse = Invoke-MgGraphRequest -Method GET -Uri $siteUri -ErrorAction Stop

                if ($siteResponse.value) {
                    $siteResponse.value | ForEach-Object {
                        $site = $_
                        $siteId = $site.id

                        try {
                            # Check for sensitivity labels on site
                            $siteLabelsUri = "https://graph.microsoft.com/beta/sites/$siteId/assignedLabels"
                            $siteLabelsResponse = Invoke-MgGraphRequest -Method GET -Uri $siteLabelsUri -ErrorAction SilentlyContinue

                            if ($siteLabelsResponse.value -and $siteLabelsResponse.value.Count -gt 0) {
                                $siteLabelsResponse.value | ForEach-Object {
                                    $results += [PSCustomObject]@{
                                        Name                 = $_.displayName
                                        Id                   = $_.id
                                        Description          = $_.description
                                        LabelType            = 'Applied to Site'
                                        AppliedTo            = $site.webUrl
                                        IsActive             = $true
                                        EncryptionEnabled    = $_.encryptionEnabled
                                        RetentionEnabled     = $_.retentionDuration -gt 0
                                        MarkingsEnabled      = if ($_.contentMarkings) { $_.contentMarkings.Count -gt 0 } else { $false }
                                        ParentId             = $_.parent.id
                                        CreatedDateTime      = $null
                                        LastModifiedDateTime = $_.lastModifiedDateTime
                                        Priority             = $_.priority
                                        Tooltip              = $_.tooltip
                                        Color                = $_.color
                                    }
                                }
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve labels for site $($site.displayName): $_"
                        }
                    }
                }
            }
            catch {
                Write-Warning "Could not retrieve site labels: $_"
            }

            # Retrieve labels applied to M365 Groups
            Write-Verbose "Retrieving sensitivity labels applied to M365 Groups..."

            try {
                $groupUri = "https://graph.microsoft.com/v1.0/groups?`$select=id,displayName,mail"
                $groupResponse = Invoke-MgGraphRequest -Method GET -Uri $groupUri -ErrorAction Stop

                if ($groupResponse.value) {
                    $groupResponse.value | ForEach-Object {
                        $group = $_
                        $groupId = $group.id

                        try {
                            # Check for assigned labels on group
                            $groupLabelsUri = "https://graph.microsoft.com/beta/groups/$($groupId)?`$select=assignedLabels"
                            $groupLabelsResponse = Invoke-MgGraphRequest -Method GET -Uri $groupLabelsUri -ErrorAction SilentlyContinue

                            if ($groupLabelsResponse.assignedLabels -and $groupLabelsResponse.assignedLabels.Count -gt 0) {
                                $groupLabelsResponse.assignedLabels | ForEach-Object {
                                    $results += [PSCustomObject]@{
                                        Name                 = $_.displayName
                                        Id                   = $_.labelId
                                        Description          = $_.description
                                        LabelType            = 'Applied to Group'
                                        AppliedTo            = "Group: $($group.displayName)"
                                        IsActive             = $true
                                        EncryptionEnabled    = $false
                                        RetentionEnabled     = $false
                                        MarkingsEnabled      = $false
                                        ParentId             = $null
                                        CreatedDateTime      = $null
                                        LastModifiedDateTime = $null
                                        Priority             = $null
                                        Tooltip              = $_.tooltip
                                        Color                = $null
                                    }
                                }
                            }
                        }
                        catch {
                            Write-Verbose "Could not retrieve labels for group $($group.displayName): $_"
                        }
                    }
                }
            }
            catch {
                Write-Warning "Could not retrieve group labels: $_"
            }
        }

        # Retrieve label policies if requested
        if ($IncludeLabelPolicies) {
            Write-Verbose "Retrieving sensitivity label policies..."

            try {
                $policiesUri = "https://graph.microsoft.com/beta/security/informationProtection/labelPolicies"
                $policiesResponse = Invoke-MgGraphRequest -Method GET -Uri $policiesUri -ErrorAction Stop

                if ($policiesResponse.value) {
                    $policiesResponse.value | ForEach-Object {
                        $results += [PSCustomObject]@{
                            Name                 = $_.displayName
                            Id                   = $_.id
                            Description          = $_.description
                            LabelType            = 'Policy'
                            AppliedTo            = 'Organization'
                            IsActive             = $_.isEnabled
                            EncryptionEnabled    = $false
                            RetentionEnabled     = $false
                            MarkingsEnabled      = $false
                            ParentId             = $null
                            CreatedDateTime      = $_.createdDateTime
                            LastModifiedDateTime = $_.lastModifiedDateTime
                            Priority             = $null
                            Tooltip              = $_.tooltip
                            Color                = $null
                        }
                    }
                }
            }
            catch {
                Write-Warning "Could not retrieve label policies: $_"
            }
        }

        if ($results.Count -eq 0) {
            Write-Verbose "No sensitivity labels found in tenant"
        }
        else {
            Write-Verbose "Retrieved $($results.Count) sensitivity label entries"
        }

        return $results

    }
    catch {
        throw "Failed to retrieve sensitivity labels: $_"
    }
}
