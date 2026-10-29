function Get-AdcsEnrollmentServicesTemplatesFromConfigurationPartition {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest, [string]$Server)

    $server = if ($Server) { $Server } else { [string]$Forest.SchemaMaster }
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext

    $base = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$configNC"
    $props = @('dNSHostName', 'certificateTemplates', 'displayName', 'name', 'distinguishedName')

    $rows = @()
    $cas = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKIEnrollmentService)' `
            -Server $server -Properties $props -ErrorAction Stop)

    foreach ($ca in $cas) {
        foreach ($t in @($ca.certificateTemplates)) {
            $rows += [pscustomobject]@{
                ForestName            = [string]$Forest.Name
                EnrollmentServiceName = [string]$ca.Name
                EnrollmentServiceDn   = [string]$ca.DistinguishedName
                TemplateName          = [string]$t
                TemplateOid           = $null
            }
        }
    }

    return @($rows)
}
