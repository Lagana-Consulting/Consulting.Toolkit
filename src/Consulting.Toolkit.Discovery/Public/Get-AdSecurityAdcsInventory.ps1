function Get-AdSecurityAdcsInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Forest,
        [Parameter(Mandatory)]
        [ValidateSet('EnterpriseCAs', 'EnrollmentServicesTemplates')]
        [string] $Mode,
        [string]$Server
    )

    switch ($Mode) {
        'EnterpriseCAs' {
            return @(Get-AdcsEnterpriseCAsFromConfigurationPartition -Forest $Forest -Server $Server)
        }
        'EnrollmentServicesTemplates' {
            return @(Get-AdcsEnrollmentServicesTemplatesFromConfigurationPartition -Forest $Forest -Server $Server)
        }
    }
}
