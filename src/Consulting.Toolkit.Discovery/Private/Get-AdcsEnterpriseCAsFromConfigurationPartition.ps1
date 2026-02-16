function Get-AdcsEnterpriseCAsFromConfigurationPartition {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest)

    $server = $Forest.SchemaMaster
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext

    $base = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$configNC"
    $props = @('dNSHostName', 'cACertificateDN', 'certificateTemplates', 'displayName', 'name', 'distinguishedName')

    $cas = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKIEnrollmentService)' `
            -Server $server -Properties $props -ErrorAction SilentlyContinue)

    foreach ($ca in $cas) {
        [pscustomobject]@{
            CAName            = $ca.Name
            DisplayName       = $ca.displayName
            DnsHostName       = $ca.dNSHostName
            DistinguishedName = $ca.DistinguishedName
            TemplateCount     = @($ca.certificateTemplates).Count
            Templates         = (@($ca.certificateTemplates) -join ';')
        }
    }
}
