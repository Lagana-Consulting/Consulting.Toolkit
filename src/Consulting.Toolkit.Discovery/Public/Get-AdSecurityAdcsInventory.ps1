function Get-AdSecurityAdcsInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Forest,
        [Parameter(Mandatory)]
        [ValidateSet('EnterpriseCAs', 'EnrollmentServicesTemplates')]
        [string] $Mode
    )

    switch ($Mode) {
        'EnterpriseCAs' {
            return @(Get-AdcsEnterpriseCAsFromConfigurationPartition -Forest $Forest)
        }
        'EnrollmentServicesTemplates' {
            return @(Get-AdcsEnrollmentServicesTemplatesFromConfigurationPartition -Forest $Forest)
        }
    }
}
