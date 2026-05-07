function Test-AdmtPrerequisite {
    <#
    .SYNOPSIS
    Test ADMT preparation prerequisites in a source or target environment.

    .DESCRIPTION
    Reads the standard or supplied ADMT preparation rules and returns checklist
    rows for the current machine/domain context. Run this in the source
    environment with -Role Source and in the target environment with -Role Target.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'Target')]
        [string]$Role,

        [string]$ConfigPath,

        [string]$OutputRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $rules = Resolve-AdmtPreparationRules -ConfigPath $ConfigPath
    $ruleSet = Get-AdmtPreparationRuleSet -Rules $rules -Role $Role
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($rule in @($ruleSet.PowerShellModules)) {
        if ($null -ne $rule) { [void]$rows.Add((Test-AdmtPowerShellModuleRule -Role $Role -Rule $rule)) }
    }

    foreach ($row in @(Test-AdmtDomainRule -Role $Role -Rule $ruleSet.Domain)) {
        [void]$rows.Add($row)
    }

    foreach ($rule in @($ruleSet.Registry)) {
        if ($null -ne $rule) { [void]$rows.Add((Test-AdmtRegistryRule -Role $Role -Rule $rule)) }
    }

    foreach ($rule in @($ruleSet.Services)) {
        if ($null -ne $rule) { [void]$rows.Add((Test-AdmtServiceRule -Role $Role -Rule $rule)) }
    }

    foreach ($rule in @($ruleSet.ServiceAccounts)) {
        if ($null -ne $rule) {
            foreach ($row in @(Test-AdmtServiceAccountRule -Role $Role -Rule $rule)) {
                [void]$rows.Add($row)
            }
        }
    }

    foreach ($rule in @($ruleSet.Trusts)) {
        if ($null -ne $rule) { [void]$rows.Add((Test-AdmtTrustRule -Role $Role -Rule $rule)) }
    }

    foreach ($rule in @($ruleSet.DnsResolution)) {
        if ($null -ne $rule) { [void]$rows.Add((Test-AdmtDnsResolutionRule -Role $Role -Rule $rule)) }
    }

    foreach ($rule in @($ruleSet.Groups)) {
        if ($null -ne $rule) { [void]$rows.Add((Test-AdmtGroupRule -Role $Role -Rule $rule)) }
    }

    return New-AdmtPreparationReport -Role $Role -Rows $rows.ToArray() -OutputRoot $OutputRoot
}
