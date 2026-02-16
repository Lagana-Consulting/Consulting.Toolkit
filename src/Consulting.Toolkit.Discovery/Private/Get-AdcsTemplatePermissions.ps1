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
            $rows += [pscustomobject]@{
                TemplateName        = $t.Name
                DisplayName         = $t.displayName
                Identity            = $ace.IdentityReference.Value
                AccessType          = [string]$ace.AccessControlType
                Rights              = [string]$ace.ActiveDirectoryRights
                Inherited           = [bool]$ace.IsInherited
                ObjectType          = [string]$ace.ObjectType
                InheritedObjectType = [string]$ace.InheritedObjectType
            }
        }
    }

    return @($rows)
}
