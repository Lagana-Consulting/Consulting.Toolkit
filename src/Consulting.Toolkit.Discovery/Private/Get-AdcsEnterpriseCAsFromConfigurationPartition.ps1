function Get-AdcsEnterpriseCAsFromConfigurationPartition {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest, [string]$Server)

    $server = if ($Server) { $Server } else { [string]$Forest.SchemaMaster }
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext

    $base = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$configNC"
    $props = @('dNSHostName', 'cACertificateDN', 'certificateTemplates', 'displayName', 'name', 'distinguishedName')

    $cas = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKIEnrollmentService)' `
            -Server $server -Properties $props -ErrorAction Stop)

    foreach ($ca in $cas) {
        [pscustomobject]@{
            ForestName             = [string]$Forest.Name
            CAName                 = [string]$ca.Name
            DnsHostName            = [string]$ca.dNSHostName
            DistinguishedName      = [string]$ca.DistinguishedName
            CertificateSubject     = [string]$ca.cACertificateDN
            CertificateSerialNumber = $null
            ValidityNotAfterUtc    = $null
            PublishedTemplates     = (@($ca.certificateTemplates) -join ';')
        }
    }
}
