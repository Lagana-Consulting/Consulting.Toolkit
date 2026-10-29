function Get-AdcsCertificateTemplates {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest, [string]$Server)

    $server = if ($Server) { $Server } else { [string]$Forest.SchemaMaster }
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext

    $base = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"
    $props = @('displayName', 'msPKI-Certificate-Name-Flag', 'msPKI-Enrollment-Flag', 'msPKI-Private-Key-Flag',
        'pKIExtendedKeyUsage', 'pKIKeyUsage', 'msPKI-RA-Signature', 'msPKI-Minimal-Key-Size',
        'msPKI-Cert-Template-OID', 'msPKI-Template-Schema-Version',
        'name', 'distinguishedName')

    $templates = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKICertificateTemplate)' `
            -Server $server -Properties $props -ErrorAction Stop)

    foreach ($t in $templates) {
        $nameFlag = [int]($t.'msPKI-Certificate-Name-Flag' -as [int])
        $enrollFlag = [int]($t.'msPKI-Enrollment-Flag' -as [int])
        $eku = @($t.pKIExtendedKeyUsage)
        $authorizedSignatures = [int]($t.'msPKI-RA-Signature' -as [int])
        $enrolleeSuppliesSubject = (($nameFlag -band 0x00000001) -ne 0)
        $requiresManagerApproval = (($enrollFlag -band 0x00000002) -ne 0)
        $clientAuth = ($eku -contains '1.3.6.1.5.5.7.3.2')
        $smartcardLogon = ($eku -contains '1.3.6.1.4.1.311.20.2.2')
        $anyPurpose = ($eku -contains '2.5.29.37.0')
        $sanRequirements = if ($enrolleeSuppliesSubject) { 'EnrolleeSuppliesSubject' } else { 'CAControlled' }
        $authenticationRequirements = if ($requiresManagerApproval -or $authorizedSignatures -gt 0) {
            (@(
                if ($requiresManagerApproval) { 'ManagerApproval' }
                if ($authorizedSignatures -gt 0) { "AuthorizedSignatures=$authorizedSignatures" }
            ) -join ';')
        } else {
            'None'
        }

        [pscustomobject]@{
            ForestName              = [string]$Forest.Name
            TemplateName            = [string]$t.displayName
            TemplateCn              = [string]$t.Name
            TemplateOid             = [string]$t.'msPKI-Cert-Template-OID'
            SchemaVersion           = [int]($t.'msPKI-Template-Schema-Version' -as [int])
            Enabled                 = $true
            EnrolleeSuppliesSubject = [bool]$enrolleeSuppliesSubject
            ClientAuth              = [bool]$clientAuth
            SmartcardLogon          = [bool]$smartcardLogon
            AnyPurpose              = [bool]$anyPurpose
            RequiresManagerApproval = [bool]$requiresManagerApproval
            AuthorizedSignatures    = $authorizedSignatures
            SANRequirements         = $sanRequirements
            AuthenticationRequirements = $authenticationRequirements
        }
    }
}
