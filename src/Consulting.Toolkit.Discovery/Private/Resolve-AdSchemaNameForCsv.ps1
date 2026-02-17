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

