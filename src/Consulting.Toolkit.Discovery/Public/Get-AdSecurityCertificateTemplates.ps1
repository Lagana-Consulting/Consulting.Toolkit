function Get-AdSecurityCertificateTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Forest,
        [Parameter(Mandatory)]
        [ValidateSet('Templates', 'TemplatePermissions')]
        [string] $Mode
    )

    switch ($Mode) {
        'Templates' {
            return @(Get-AdcsCertificateTemplates -Forest $Forest)
        }
        'TemplatePermissions' {
            return @(Get-AdcsTemplatePermissions -Forest $Forest)
        }
    }
}
