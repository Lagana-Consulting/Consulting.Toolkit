function Get-AdcsTemplatePermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Forest, [string]$Server)

    $server = if ($Server) { $Server } else { [string]$Forest.SchemaMaster }
    $root = Get-ADRootDSE -Server $server -ErrorAction Stop
    $configNC = $root.configurationNamingContext
    $base = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configNC"

    $templates = @(Get-ADObject -SearchBase $base -LDAPFilter '(objectClass=pKICertificateTemplate)' `
            -Server $server -Properties nTSecurityDescriptor, name, displayName -ErrorAction Stop)

    $rows = @()

    foreach ($t in $templates) {
        $sd = $null
        try {
            $sd = Get-ADObject -Identity $t.DistinguishedName -Server $server `
                -Properties nTSecurityDescriptor -ErrorAction Stop |
            Select-Object -ExpandProperty nTSecurityDescriptor
            if (-not $sd) { throw "No security descriptor was returned for '$($t.DistinguishedName)'." }
        } catch {
            Write-AdDiscoveryCollectionIssue -Message "Could not read certificate template permissions: $($t.DistinguishedName)" -ErrorRecord $_
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
