function Get-AdSecurityCertificateTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Forest,
        [Parameter(Mandatory)]
        [ValidateSet('Templates', 'TemplatePermissions')]
        [string] $Mode,
        [string]$Server
    )

    switch ($Mode) {
        'Templates' {
            return @(Get-AdcsCertificateTemplates -Forest $Forest -Server $Server)
        }
        'TemplatePermissions' {
            return @(Get-AdcsTemplatePermissions -Forest $Forest -Server $Server)
        }
    }
}
