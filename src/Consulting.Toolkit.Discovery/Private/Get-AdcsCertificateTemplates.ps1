function Get-AdcsCertificateTemplates {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest)

    $server = $Forest.SchemaMaster
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext

    $base = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
    $props = @('displayName', 'msPKI-Certificate-Name-Flag', 'msPKI-Enrollment-Flag', 'msPKI-Private-Key-Flag',
        'pKIExtendedKeyUsage', 'pKIKeyUsage', 'msPKI-RA-Signature', 'msPKI-Minimal-Key-Size',
        'name', 'distinguishedName')

    $templates = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKICertificateTemplate)' `
            -Server $server -Properties $props -ErrorAction SilentlyContinue)

    foreach ($t in $templates) {
        [pscustomobject]@{
            TemplateName      = $t.Name
            DisplayName       = $t.displayName
            DistinguishedName = $t.DistinguishedName
            MinKeySize        = $t.'msPKI-Minimal-Key-Size'
            EnrollmentFlag    = $t.'msPKI-Enrollment-Flag'
            NameFlag          = $t.'msPKI-Certificate-Name-Flag'
            PrivateKeyFlag    = $t.'msPKI-Private-Key-Flag'
            EKU               = (@($t.pKIExtendedKeyUsage) -join ';')
        }
    }
}
