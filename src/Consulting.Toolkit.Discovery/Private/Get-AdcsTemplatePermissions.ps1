function Get-AdcsTemplatePermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest)

    $server = $Forest.SchemaMaster
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext
    $base = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"

    $templates = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKICertificateTemplate)' `
            -Server $server -Properties nTSecurityDescriptor, name, displayName -ErrorAction SilentlyContinue)

    $rows = @()

    foreach ($t in $templates) {
        $sd = $null
        try {
            $sd = Get-ADObject -Identity $t.DistinguishedName -Server $server `
                -Properties nTSecurityDescriptor -ErrorAction Stop |
            Select-Object -ExpandProperty nTSecurityDescriptor
        } catch {
            continue
        }

        foreach ($ace in $sd.Access) {
            $principal = [string]$ace.IdentityReference.Value
            $principalSid = $null
            if ($principal -match '^S-\d-\d+-.+') {
                $principalSid = $principal
            }

            $rows += [pscustomobject]@{
                ForestName   = [string]$Forest.Name
                TemplateName = [string]$t.Name
                Principal    = $principal
                PrincipalSid = $principalSid
                Right        = [string]$ace.ActiveDirectoryRights
                AccessType   = [string]$ace.AccessControlType
                Inherited    = [bool]$ace.IsInherited
            }
        }
    }

    return @($rows)
}
