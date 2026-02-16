function Get-AdcsEnrollmentServicesTemplatesFromConfigurationPartition {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest)

    $server = $Forest.SchemaMaster
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext

    $base = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$configNC"
    $props = @('dNSHostName', 'certificateTemplates', 'displayName', 'name', 'distinguishedName')

    $rows = @()
    $cas = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKIEnrollmentService)' `
            -Server $server -Properties $props -ErrorAction SilentlyContinue)

    foreach ($ca in $cas) {
        foreach ($t in @($ca.certificateTemplates)) {
            $rows += [pscustomobject]@{
                CAName              = $ca.Name
                DnsHostName         = $ca.dNSHostName
                TemplateName        = $t
                EnrollmentServiceDn = $ca.DistinguishedName
            }
        }
    }

    return @($rows)
}
