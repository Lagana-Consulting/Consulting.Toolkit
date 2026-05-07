function Invoke-AdmtPreparation {
    <#
    .SYNOPSIS
    Apply configured ADMT preparation prerequisites for the current environment.

    .DESCRIPTION
    Applies concrete registry, service, and configured group membership rules for
    the selected role. The command supports -WhatIf and returns a fresh
    Test-AdmtPrerequisite report after attempting changes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Source', 'Target')]
        [string]$Role,

        [string]$ConfigPath,

        [securestring]$ServiceAccountPassword,

        [string]$OutputRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $rules = Resolve-AdmtPreparationRules -ConfigPath $ConfigPath
    $ruleSet = Get-AdmtPreparationRuleSet -Rules $rules -Role $Role

    foreach ($rule in @($ruleSet.Registry)) {
        if ($null -eq $rule) { continue }

        $target = "$($rule.Path)\$($rule.ValueName)"
        if ($PSCmdlet.ShouldProcess($target, "Set registry value to $($rule.ExpectedValue)")) {
            if (-not (Test-Path -LiteralPath ([string]$rule.Path))) {
                New-Item -Path ([string]$rule.Path) -Force | Out-Null
            }

            $propertyType = if ($rule.ValueType) { [string]$rule.ValueType } else { 'DWord' }
            New-ItemProperty `
                -LiteralPath ([string]$rule.Path) `
                -Name ([string]$rule.ValueName) `
                -Value $rule.ExpectedValue `
                -PropertyType $propertyType `
                -Force | Out-Null
        }
    }

    foreach ($rule in @($ruleSet.Services)) {
        if ($null -eq $rule) { continue }

        $serviceName = [string]$rule.Name
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Warning "Service not found: $serviceName"
            continue
        }

        if ($rule.ExpectedStartType -and $PSCmdlet.ShouldProcess($serviceName, "Set service startup type to $($rule.ExpectedStartType)")) {
            Set-Service -Name $serviceName -StartupType ([string]$rule.ExpectedStartType)
        }

        if ($rule.ExpectedStatus -eq 'Running' -and $service.Status -ne 'Running') {
            if ($PSCmdlet.ShouldProcess($serviceName, 'Start service')) {
                Start-Service -Name $serviceName
            }
        }
    }

    foreach ($rule in @($ruleSet.Groups)) {
        if ($null -eq $rule) { continue }

        $members = @($rule.Members | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($members.Count -eq 0) { continue }

        Import-Module ActiveDirectory -ErrorAction Stop
        foreach ($member in $members) {
            $target = "$($rule.Name) <= $member"
            if ($PSCmdlet.ShouldProcess($target, 'Add AD group member')) {
                Add-ADGroupMember -Identity ([string]$rule.Name) -Members ([string]$member) -ErrorAction Stop
            }
        }
    }

    foreach ($rule in @($ruleSet.ServiceAccounts)) {
        if ($null -eq $rule) { continue }

        $requiredGroups = @(Get-AdmtObjectProperty -InputObject $rule -Name 'RequiredGroups' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $createIfMissing = ConvertTo-AdmtPreparationBoolean -Value (Get-AdmtObjectProperty -InputObject $rule -Name 'CreateIfMissing')
        if ($requiredGroups.Count -eq 0 -and -not $createIfMissing) { continue }

        Import-Module ActiveDirectory -ErrorAction Stop
        $account = $null
        try {
            $account = Get-AdmtServiceAccount -Rule $rule
        }
        catch {
            $account = $null
        }

        if ($null -eq $account) {
            if ($createIfMissing) {
                if ($null -eq $ServiceAccountPassword) {
                    throw "Service account $(Get-AdmtServiceAccountLabel -Rule $rule) is missing and CreateIfMissing is true, but -ServiceAccountPassword was not supplied."
                }

                $account = New-AdmtServiceAccount -Rule $rule -Password $ServiceAccountPassword -WhatIf:$WhatIfPreference
            }
            else {
                Write-Warning "Service account not found and CreateIfMissing is false: $(Get-AdmtServiceAccountLabel -Rule $rule)"
                continue
            }
        }

        if ($null -eq $account) {
            Write-Warning "Service account is not available after create attempt: $(Get-AdmtServiceAccountLabel -Rule $rule)"
            continue
        }

        foreach ($groupName in $requiredGroups) {
            $group = Get-ADGroup -Identity ([string]$groupName) -ErrorAction Stop
            $memberships = @(Get-ADPrincipalGroupMembership -Identity $account -ErrorAction Stop)
            $isMember = @($memberships | Where-Object {
                $_.DistinguishedName -eq $group.DistinguishedName -or
                $_.SID -eq $group.SID -or
                $_.SamAccountName -eq $group.SamAccountName -or
                $_.Name -eq $group.Name
            }).Count -gt 0

            if ($isMember) {
                continue
            }

            $target = "$groupName <= $($account.SamAccountName)"
            if ($PSCmdlet.ShouldProcess($target, 'Add service account to AD group')) {
                Add-ADGroupMember -Identity $group -Members $account -ErrorAction Stop
            }
        }
    }

    foreach ($rule in @($ruleSet.Trusts)) {
        if ($null -eq $rule) { continue }

        $targetDomain = [string](Get-AdmtObjectProperty -InputObject $rule -Name 'TargetDomain')
        if ([string]::IsNullOrWhiteSpace($targetDomain)) { continue }

        Import-Module ActiveDirectory -ErrorAction Stop
        $trust = Resolve-AdmtTrust -TargetDomain $targetDomain
        if ($null -eq $trust) {
            Write-Warning "Trust not found and will not be created automatically: $targetDomain"
            continue
        }

        $sidFiltering = Get-AdmtObjectProperty -InputObject $rule -Name 'RequireSidFilteringQuarantined'
        if ($null -ne $sidFiltering) {
            Set-AdmtTrustBooleanProperty `
                -Trust $trust `
                -ParameterName 'SIDFilteringQuarantined' `
                -Value (ConvertTo-AdmtPreparationBoolean -Value $sidFiltering) `
                -WhatIf:$WhatIfPreference
        }

        $selectiveAuthentication = Get-AdmtObjectProperty -InputObject $rule -Name 'RequireSelectiveAuthentication'
        if ($null -ne $selectiveAuthentication) {
            Set-AdmtTrustBooleanProperty `
                -Trust $trust `
                -ParameterName 'SelectiveAuthentication' `
                -Value (ConvertTo-AdmtPreparationBoolean -Value $selectiveAuthentication) `
                -WhatIf:$WhatIfPreference
        }

        $transitive = Get-AdmtObjectProperty -InputObject $rule -Name 'RequireTransitive'
        if ($null -ne $transitive) {
            Write-Warning "RequireTransitive is tested but not automatically changed. Trust type/transitivity changes should be planned explicitly."
        }
    }

    Test-AdmtPrerequisite -Role $Role -ConfigPath $ConfigPath -OutputRoot $OutputRoot
}
