function Resolve-AdSchemaNameForCsv {
    <#
      .SYNOPSIS
      Maps an output CSV filename to a schema name used by Get-AdSchemaDefinitions / Export-AdSchemas.

      .DESCRIPTION
      PS5.1-safe regex matcher. Returns $null if no mapping exists.
      Intended for Export-AdCsvSafe -SchemaName <name>.

      .PARAMETER Path
      Full output path (or filename). Uses leaf filename for matching.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $file = Split-Path -Path $Path -Leaf

    # Ordered patterns: first match wins
    $map = @(
        # Core discovery datasets
        @{ Pattern = '^AD__Forest__Summary__Forest\.csv$'; Schema = 'Forest_Summary' }
        @{ Pattern = '^AD__Forest__Identity__UpnSuffixes__Forest\.csv$'; Schema = 'Forest_UPNSuffixes' }
        @{ Pattern = '^AD__Forest__Network__Sites__Forest\.csv$'; Schema = 'Forest_Sites' }
        @{ Pattern = '^AD__Forest__Network__Subnets__Forest\.csv$'; Schema = 'Forest_Subnets' }
        @{ Pattern = '^AD__Forest__Network__SiteLinks__Forest\.csv$'; Schema = 'Forest_SiteLinks' }
        @{ Pattern = '^AD__Domain__Summary__Domain-.*\.csv$'; Schema = 'Domain_Summary' }
        @{ Pattern = '^AD__Domain__Identity__Users__Domain-.*\.csv$'; Schema = 'Users' }
        @{ Pattern = '^AD__Domain__Identity__Groups__Domain-.*\.csv$'; Schema = 'Groups' }
        @{ Pattern = '^AD__Domain__Identity__ComputersAll__Domain-.*\.csv$'; Schema = 'Computers' }
        @{ Pattern = '^AD__Domain__Identity__Spns__Domain-.*\.csv$'; Schema = 'SPNs' }
        @{ Pattern = '^AD__Domain__Security__PrivilegedAccounts__Domain-.*\.csv$'; Schema = 'PrivilegedAccounts' }
        @{ Pattern = '^AD__Domain__GPO__Inventory__Domain-.*\.csv$'; Schema = 'GpoInventory' }

        # --- Forest Security ADCS ---
        @{ Pattern = '^AD__Forest__Security__ADCS__EnterpriseCAs__Forest\.csv$'; Schema = 'Forest_Security_ADCS_EnterpriseCAs' }
        @{ Pattern = '^AD__Forest__Security__ADCS__EnrollmentServicesTemplates__Forest\.csv$'; Schema = 'Forest_Security_ADCS_EnrollmentServicesTemplates' }
        @{ Pattern = '^AD__Forest__Security__ADCS__CertificateTemplates__Forest\.csv$'; Schema = 'Forest_Security_ADCS_CertificateTemplates' }
        @{ Pattern = '^AD__Forest__Security__ADCS__CertificateTemplatePermissions__Forest\.csv$'; Schema = 'Forest_Security_ADCS_CertificateTemplatePermissions' }
        @{ Pattern = '^AD__Forest__Security__Trusts__Forest\.csv$'; Schema = 'Forest_Security_Trusts' }

        # --- Domain Security Tier0 / Privileged ---
        @{ Pattern = '^AD__Domain__Security__PrivilegedGroupMembers__Domain-.*\.csv$'; Schema = 'Domain_Security_PrivilegedGroupMembers' }
        @{ Pattern = '^AD__Domain__Security__AdminCountObjects__Domain-.*\.csv$'; Schema = 'Domain_Security_AdminCountObjects' }
        @{ Pattern = '^AD__Domain__Security__ProtectedUsers__Domain-.*\.csv$'; Schema = 'Domain_Security_ProtectedUsers' }
        @{ Pattern = '^AD__Domain__Security__AdminSdHolderImpact__Domain-.*\.csv$'; Schema = 'AdminSdHolderImpact' }

        # --- Domain Identity Group Membership Details ---
        @{ Pattern = '^AD__Domain__Identity__UsersDisabled__Domain-.*\.csv$'; Schema = 'UserStatus_DisabledUsers' }
        @{ Pattern = '^AD__Domain__Identity__UsersInactive__Domain-.*\.csv$'; Schema = 'UserStatus_InactiveUsers' }
        @{ Pattern = '^AD__Domain__Identity__GroupsEmpty__Domain-.*\.csv$'; Schema = 'GroupMembership_EmptyGroups' }
        @{ Pattern = '^AD__Domain__Identity__GroupsSingleMember__Domain-.*\.csv$'; Schema = 'GroupMembership_SingleMemberGroups' }
        @{ Pattern = '^AD__Domain__Identity__GroupsWithDisabledOrInactiveMembers__Domain-.*\.csv$'; Schema = 'GroupMembership_DisabledOrInactiveMembers' }
        @{ Pattern = '^AD__Domain__Identity__ComputersInactiveWorkstations__Domain-.*\.csv$'; Schema = 'ComputerStatus_InactiveWorkstations' }
        @{ Pattern = '^AD__Domain__Identity__ComputersInactiveServers__Domain-.*\.csv$'; Schema = 'ComputerStatus_InactiveServers' }

        # --- Domain Security Phase 1 ---
        @{ Pattern = '^AD__Domain__Security__RecentlyCreatedObjects__Domain-.*\.csv$'; Schema = 'Domain_Security_RecentlyCreatedObjects' }
        @{ Pattern = '^AD__Domain__Security__BuiltInAdministratorSignals__Domain-.*\.csv$'; Schema = 'Domain_Security_BuiltInAdministratorSignals' }
        @{ Pattern = '^AD__Domain__Security__AsrepRoastableUsers__Domain-.*\.csv$'; Schema = 'Domain_Security_AsrepRoastableUsers' }
        @{ Pattern = '^AD__Domain__Security__PrivilegedPasswordAge__Domain-.*\.csv$'; Schema = 'Domain_Security_PrivilegedPasswordAge' }
        @{ Pattern = '^AD__Domain__GPO__Delegation__Domain-.*\.csv$'; Schema = 'Domain_GPO_Delegation' }

        # --- Domain Security Delegation ---
        @{ Pattern = '^AD__Domain__Security__DelegationUnconstrained__Domain-.*\.csv$'; Schema = 'Domain_Security_DelegationUnconstrained' }
        @{ Pattern = '^AD__Domain__Security__DelegationConstrained__Domain-.*\.csv$'; Schema = 'Domain_Security_DelegationConstrained' }
        @{ Pattern = '^AD__Domain__Security__DelegationProtocolTransition__Domain-.*\.csv$'; Schema = 'Domain_Security_DelegationProtocolTransition' }
        @{ Pattern = '^AD__Domain__Security__DelegationRBCD__Domain-.*\.csv$'; Schema = 'Domain_Security_DelegationRBCD' }

        # --- Domain Security SPN / DC signals ---
        @{ Pattern = '^AD__Domain__Security__SpnAccounts__Domain-.*\.csv$'; Schema = 'Domain_Security_SpnAccounts' }
        @{ Pattern = '^AD__Domain__Security__DomainControllerSecuritySignals__Domain-.*\.csv$'; Schema = 'Domain_Security_DomainControllerSecuritySignals' }
    )

    foreach ($entry in $map) {
        if ($file -match $entry.Pattern) {
            return $entry.Schema
        }
    }

    return $null
}

