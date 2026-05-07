function Get-AdmtPreparationTimestamp {
    [CmdletBinding()]
    param()

    return Get-Date -Format 'yyyyMMdd-HHmmss'
}

function Resolve-AdmtPreparationRules {
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $defaultPath = Join-Path $moduleRoot 'config\AdmtPreparationRules.Standard.json'
    $path = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath } else { $defaultPath }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "ADMT preparation config not found: $path"
    }

    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-AdmtPreparationRuleSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Rules,
        [Parameter(Mandatory)][ValidateSet('Source', 'Target')][string]$Role
    )

    $roleRules = $Rules.$Role
    $bothRules = $Rules.Both

    $roleDomain = Get-AdmtObjectProperty -InputObject $roleRules -Name 'Domain'
    $bothDomain = Get-AdmtObjectProperty -InputObject $bothRules -Name 'Domain'

    return [pscustomobject]@{
        Registry          = @(Get-AdmtObjectProperty -InputObject $bothRules -Name 'Registry') + @(Get-AdmtObjectProperty -InputObject $roleRules -Name 'Registry')
        Services          = @(Get-AdmtObjectProperty -InputObject $bothRules -Name 'Services') + @(Get-AdmtObjectProperty -InputObject $roleRules -Name 'Services')
        Groups            = @(Get-AdmtObjectProperty -InputObject $bothRules -Name 'Groups') + @(Get-AdmtObjectProperty -InputObject $roleRules -Name 'Groups')
        ServiceAccounts   = @(Get-AdmtObjectProperty -InputObject $bothRules -Name 'ServiceAccounts') + @(Get-AdmtObjectProperty -InputObject $roleRules -Name 'ServiceAccounts')
        Trusts            = @(Get-AdmtObjectProperty -InputObject $bothRules -Name 'Trusts') + @(Get-AdmtObjectProperty -InputObject $roleRules -Name 'Trusts')
        DnsResolution     = @(Get-AdmtObjectProperty -InputObject $bothRules -Name 'DnsResolution') + @(Get-AdmtObjectProperty -InputObject $roleRules -Name 'DnsResolution')
        PowerShellModules = @(Get-AdmtObjectProperty -InputObject $bothRules -Name 'PowerShellModules') + @(Get-AdmtObjectProperty -InputObject $roleRules -Name 'PowerShellModules')
        Domain            = if ($roleDomain) { $roleDomain } else { $bothDomain }
    }
}

function Get-AdmtObjectProperty {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function ConvertTo-AdmtPreparationBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes', 'y')) { return $true }
    if ($text -in @('false', '0', 'no', 'n')) { return $false }
    return $Default
}

function ConvertTo-AdmtLdapFilterValue {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return $Value.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29').Replace([string][char]0, '\00')
}

function New-AdmtPreparationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Severity = 'Info',
        [string]$CurrentValue = '',
        [string]$ExpectedValue = '',
        [string]$Recommendation = '',
        [string]$Action = '',
        [string]$ErrorMessage = ''
    )

    return [pscustomobject]@{
        Role           = $Role
        Category       = $Category
        Name           = $Name
        Status         = $Status
        Severity       = $Severity
        CurrentValue   = $CurrentValue
        ExpectedValue  = $ExpectedValue
        Recommendation = $Recommendation
        Action         = $Action
        ErrorMessage   = $ErrorMessage
    }
}

function Test-AdmtRegistryRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$Rule
    )

    $expected = $Rule.ExpectedValue
    $current = $null
    $status = 'Fail'
    $errorMessage = ''

    try {
        if (Test-Path -LiteralPath ([string]$Rule.Path)) {
            $property = Get-ItemProperty -LiteralPath ([string]$Rule.Path) -Name ([string]$Rule.ValueName) -ErrorAction SilentlyContinue
            if ($property) {
                $current = $property.([string]$Rule.ValueName)
            }
        }

        if ($null -ne $current -and ([string]$current) -eq ([string]$expected)) {
            $status = 'Pass'
        }
        else {
            $status = 'Fail'
        }
    }
    catch {
        $status = 'Fail'
        $errorMessage = $_.Exception.Message
    }

    New-AdmtPreparationResult `
        -Role $Role `
        -Category 'Registry' `
        -Name ([string]$Rule.Name) `
        -Status $status `
        -Severity ([string]$Rule.Severity) `
        -CurrentValue $(if ($null -eq $current) { '<missing>' } else { [string]$current }) `
        -ExpectedValue "$($Rule.Path)\$($Rule.ValueName) = $expected" `
        -Recommendation ([string]$Rule.Recommendation) `
        -ErrorMessage $errorMessage
}

function Test-AdmtServiceRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$Rule
    )

    $status = 'Fail'
    $current = '<missing>'
    $errorMessage = ''

    try {
        $service = Get-Service -Name ([string]$Rule.Name) -ErrorAction SilentlyContinue
        if ($service) {
            $cimService = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($Rule.Name)'" -ErrorAction Stop
            $current = "Status=$($service.Status); StartType=$($cimService.StartMode)"
            $expectedStartType = ConvertTo-AdmtCimStartMode -StartType ([string]$Rule.ExpectedStartType)

            if (([string]$service.Status -eq [string]$Rule.ExpectedStatus) -and ([string]$cimService.StartMode -eq $expectedStartType)) {
                $status = 'Pass'
            }
            else {
                $status = 'Fail'
            }
        }
    }
    catch {
        $status = 'Fail'
        $errorMessage = $_.Exception.Message
    }

    New-AdmtPreparationResult `
        -Role $Role `
        -Category 'Service' `
        -Name ([string]$Rule.Name) `
        -Status $status `
        -Severity ([string]$Rule.Severity) `
        -CurrentValue $current `
        -ExpectedValue "Status=$($Rule.ExpectedStatus); StartType=$($Rule.ExpectedStartType)" `
        -Recommendation ([string]$Rule.Recommendation) `
        -ErrorMessage $errorMessage
}

function Test-AdmtPowerShellModuleRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$Rule
    )

    $module = Get-Module -ListAvailable -Name ([string]$Rule.Name) | Select-Object -First 1
    $status = if ($module) { 'Pass' } else { 'Fail' }
    $current = if ($module) { "Available: $($module.Version)" } else { '<missing>' }

    New-AdmtPreparationResult `
        -Role $Role `
        -Category 'PowerShellModule' `
        -Name ([string]$Rule.Name) `
        -Status $status `
        -Severity ([string]$Rule.Severity) `
        -CurrentValue $current `
        -ExpectedValue 'Installed' `
        -Recommendation ([string]$Rule.Recommendation)
}

function Test-AdmtDomainRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [AllowNull()]$Rule
    )

    if ($null -eq $Rule) {
        return @()
    }

    $status = 'Fail'
    $current = ''
    $errorMessage = ''

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $domain = Get-ADDomain -ErrorAction Stop
        $current = "DNSRoot=$($domain.DNSRoot); DomainMode=$($domain.DomainMode); DomainSID=$($domain.DomainSID)"
        $status = 'Pass'
    }
    catch {
        $status = 'Fail'
        $errorMessage = $_.Exception.Message
    }

    New-AdmtPreparationResult `
        -Role $Role `
        -Category 'Domain' `
        -Name 'Current domain access' `
        -Status $status `
        -Severity ([string]$Rule.Severity) `
        -CurrentValue $current `
        -ExpectedValue "Readable Active Directory domain; MinimumDomainMode=$($Rule.MinimumDomainMode)" `
        -Recommendation ([string]$Rule.Recommendation) `
        -ErrorMessage $errorMessage
}

function Test-AdmtGroupRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$Rule
    )

    $members = @($Rule.Members | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $status = if ($members.Count -gt 0) { 'Fail' } else { 'Manual' }
    $current = if ($members.Count -gt 0) { '' } else { 'Not changed by default configuration' }
    $errorMessage = ''

    if ($members.Count -eq 0) {
        return New-AdmtPreparationResult `
            -Role $Role `
            -Category 'Group' `
            -Name ([string]$Rule.Name) `
            -Status $status `
            -Severity ([string]$Rule.Severity) `
            -CurrentValue $current `
            -ExpectedValue 'Manual validation' `
            -Recommendation ([string]$Rule.Recommendation)
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $group = Get-ADGroup -Identity ([string]$Rule.Name) -ErrorAction Stop
        $existingMembers = @(Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop | ForEach-Object { $_.SamAccountName })
        $missing = @($members | Where-Object { $existingMembers -notcontains $_ })
        $status = if ($missing.Count -eq 0) { 'Pass' } else { 'Fail' }
        $current = if ($missing.Count -eq 0) { 'All configured members present' } else { 'Missing: ' + ($missing -join ', ') }
    }
    catch {
        $status = 'Fail'
        $errorMessage = $_.Exception.Message
    }

    New-AdmtPreparationResult `
        -Role $Role `
        -Category 'Group' `
        -Name ([string]$Rule.Name) `
        -Status $status `
        -Severity ([string]$Rule.Severity) `
        -CurrentValue $current `
        -ExpectedValue $(if ($members.Count -gt 0) { 'Members: ' + ($members -join ', ') } else { 'Manual validation' }) `
        -Recommendation ([string]$Rule.Recommendation) `
        -ErrorMessage $errorMessage
}

function Test-AdmtServiceAccountRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$Rule
    )

    $rows = New-Object System.Collections.Generic.List[object]
    $accountLabel = Get-AdmtServiceAccountLabel -Rule $Rule
    $sam = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'SamAccountName')
    $upn = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'UserPrincipalName')
    $requiredGroups = @(Get-AdmtObjectProperty -InputObject $Rule -Name 'RequiredGroups' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $severity = if (Get-AdmtObjectProperty -InputObject $Rule -Name 'Severity') { [string]$Rule.Severity } else { 'Fail' }
    $recommendation = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'Recommendation')

    if ([string]::IsNullOrWhiteSpace($sam) -and [string]::IsNullOrWhiteSpace($upn)) {
        [void]$rows.Add((New-AdmtPreparationResult `
            -Role $Role `
            -Category 'ServiceAccount' `
            -Name ([string]$Rule.Name) `
            -Status 'Manual' `
            -Severity 'Info' `
            -CurrentValue 'No service account configured' `
            -ExpectedValue 'SamAccountName or UserPrincipalName' `
            -Recommendation $recommendation))
        return $rows.ToArray()
    }

    $account = $null
    $errorMessage = ''
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $account = Get-AdmtServiceAccount -Rule $Rule
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    if ($null -eq $account) {
        [void]$rows.Add((New-AdmtPreparationResult `
            -Role $Role `
            -Category 'ServiceAccount' `
            -Name $accountLabel `
            -Status 'Fail' `
            -Severity $severity `
            -CurrentValue '<missing>' `
            -ExpectedValue 'Enabled AD user account' `
            -Recommendation $recommendation `
            -ErrorMessage $errorMessage))
        return $rows.ToArray()
    }

    $enabledStatus = if ($account.Enabled) { 'Pass' } else { 'Fail' }
    [void]$rows.Add((New-AdmtPreparationResult `
        -Role $Role `
        -Category 'ServiceAccount' `
        -Name $accountLabel `
        -Status $enabledStatus `
        -Severity $severity `
        -CurrentValue "DistinguishedName=$($account.DistinguishedName); Enabled=$($account.Enabled)" `
        -ExpectedValue 'Enabled AD user account' `
        -Recommendation $recommendation))

    if ($requiredGroups.Count -eq 0) {
        [void]$rows.Add((New-AdmtPreparationResult `
            -Role $Role `
            -Category 'ServiceAccountPermission' `
            -Name $accountLabel `
            -Status 'Manual' `
            -Severity 'Info' `
            -CurrentValue 'No required groups configured' `
            -ExpectedValue 'RequiredGroups list' `
            -Recommendation 'Add role-specific required group memberships to the service account rule when the migration design is known.'))
        return $rows.ToArray()
    }

    foreach ($groupName in $requiredGroups) {
        $group = $null
        $isMember = $false
        $groupError = ''

        try {
            $group = Get-ADGroup -Identity ([string]$groupName) -ErrorAction Stop
            $memberships = @(Get-ADPrincipalGroupMembership -Identity $account -ErrorAction Stop)
            $isMember = @($memberships | Where-Object {
                $_.DistinguishedName -eq $group.DistinguishedName -or
                $_.SID -eq $group.SID -or
                $_.SamAccountName -eq $group.SamAccountName -or
                $_.Name -eq $group.Name
            }).Count -gt 0
        }
        catch {
            $groupError = $_.Exception.Message
        }

        [void]$rows.Add((New-AdmtPreparationResult `
            -Role $Role `
            -Category 'ServiceAccountPermission' `
            -Name "$accountLabel -> $groupName" `
            -Status $(if ($isMember) { 'Pass' } else { 'Fail' }) `
            -Severity $severity `
            -CurrentValue $(if ($isMember) { 'Member' } elseif ($group) { 'Not a member' } else { '<group lookup failed>' }) `
            -ExpectedValue 'Group membership' `
            -Recommendation $recommendation `
            -ErrorMessage $groupError))
    }

    return $rows.ToArray()
}

function Get-AdmtServiceAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Rule
    )

    $sam = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'SamAccountName')
    $upn = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'UserPrincipalName')

    if (-not [string]::IsNullOrWhiteSpace($sam)) {
        return Get-ADUser -Identity $sam -Properties Enabled, UserPrincipalName, DistinguishedName -ErrorAction Stop
    }

    if (-not [string]::IsNullOrWhiteSpace($upn)) {
        $escapedUpn = ConvertTo-AdmtLdapFilterValue -Value $upn
        return Get-ADUser -LDAPFilter "(userPrincipalName=$escapedUpn)" -Properties Enabled, UserPrincipalName, DistinguishedName -ErrorAction Stop
    }

    return $null
}

function Get-AdmtServiceAccountLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Rule
    )

    $sam = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'SamAccountName')
    $upn = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'UserPrincipalName')
    $name = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'Name')

    if (-not [string]::IsNullOrWhiteSpace($sam)) { return $sam }
    if (-not [string]::IsNullOrWhiteSpace($upn)) { return $upn }
    return $name
}

function Test-AdmtTrustRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$Rule
    )

    $targetDomain = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'TargetDomain')
    $severity = if (Get-AdmtObjectProperty -InputObject $Rule -Name 'Severity') { [string]$Rule.Severity } else { 'Fail' }
    $recommendation = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'Recommendation')

    if ([string]::IsNullOrWhiteSpace($targetDomain)) {
        return New-AdmtPreparationResult `
            -Role $Role `
            -Category 'Trust' `
            -Name ([string]$Rule.Name) `
            -Status 'Manual' `
            -Severity 'Info' `
            -CurrentValue 'No target domain configured' `
            -ExpectedValue 'TargetDomain' `
            -Recommendation $recommendation
    }

    $trust = $null
    $status = 'Fail'
    $current = '<missing>'
    $expectedMessages = New-Object System.Collections.Generic.List[string]
    $failures = New-Object System.Collections.Generic.List[string]
    $errorMessage = ''

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $trust = Resolve-AdmtTrust -TargetDomain $targetDomain
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    if ($null -eq $trust) {
        return New-AdmtPreparationResult `
            -Role $Role `
            -Category 'Trust' `
            -Name $targetDomain `
            -Status 'Fail' `
            -Severity $severity `
            -CurrentValue $current `
            -ExpectedValue 'Existing AD trust' `
            -Recommendation $recommendation `
            -ErrorMessage $errorMessage
    }

    $current = "Name=$($trust.Name); Direction=$($trust.Direction); TrustType=$($trust.TrustType); ForestTransitive=$($trust.ForestTransitive); SIDFilteringQuarantined=$($trust.SIDFilteringQuarantined); SelectiveAuthentication=$($trust.SelectiveAuthentication)"

    $expectedDirection = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'ExpectedDirection')
    if (-not [string]::IsNullOrWhiteSpace($expectedDirection)) {
        [void]$expectedMessages.Add("Direction=$expectedDirection")
        if ([string]$trust.Direction -ne $expectedDirection) {
            [void]$failures.Add("Direction is $($trust.Direction)")
        }
    }

    $expectedTrustType = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'ExpectedTrustType')
    if (-not [string]::IsNullOrWhiteSpace($expectedTrustType)) {
        [void]$expectedMessages.Add("TrustType=$expectedTrustType")
        if ([string]$trust.TrustType -ne $expectedTrustType) {
            [void]$failures.Add("TrustType is $($trust.TrustType)")
        }
    }

    Add-AdmtBooleanTrustExpectation -Rule $Rule -RuleProperty 'RequireTransitive' -Trust $trust -TrustProperty 'ForestTransitive' -ExpectedMessages $expectedMessages -Failures $failures
    Add-AdmtBooleanTrustExpectation -Rule $Rule -RuleProperty 'RequireSidFilteringQuarantined' -Trust $trust -TrustProperty 'SIDFilteringQuarantined' -ExpectedMessages $expectedMessages -Failures $failures
    Add-AdmtBooleanTrustExpectation -Rule $Rule -RuleProperty 'RequireSelectiveAuthentication' -Trust $trust -TrustProperty 'SelectiveAuthentication' -ExpectedMessages $expectedMessages -Failures $failures

    $status = if ($failures.Count -eq 0) { 'Pass' } else { 'Fail' }
    $expected = if ($expectedMessages.Count -gt 0) { $expectedMessages -join '; ' } else { 'Existing AD trust' }
    $errorMessage = if ($failures.Count -gt 0) { $failures -join '; ' } else { '' }

    New-AdmtPreparationResult `
        -Role $Role `
        -Category 'Trust' `
        -Name $targetDomain `
        -Status $status `
        -Severity $severity `
        -CurrentValue $current `
        -ExpectedValue $expected `
        -Recommendation $recommendation `
        -ErrorMessage $errorMessage
}

function Add-AdmtBooleanTrustExpectation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][string]$RuleProperty,
        [Parameter(Mandatory)]$Trust,
        [Parameter(Mandatory)][string]$TrustProperty,
        [Parameter(Mandatory)]$ExpectedMessages,
        [Parameter(Mandatory)]$Failures
    )

    $expected = Get-AdmtObjectProperty -InputObject $Rule -Name $RuleProperty
    if ($null -eq $expected) {
        return
    }

    $expectedBoolean = ConvertTo-AdmtPreparationBoolean -Value $expected
    $actualBoolean = ConvertTo-AdmtPreparationBoolean -Value (Get-AdmtObjectProperty -InputObject $Trust -Name $TrustProperty)
    [void]$ExpectedMessages.Add("$TrustProperty=$expectedBoolean")

    if ($actualBoolean -ne $expectedBoolean) {
        [void]$Failures.Add("$TrustProperty is $actualBoolean")
    }
}

function Resolve-AdmtTrust {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetDomain
    )

    try {
        return Get-ADTrust -Identity $TargetDomain -Properties * -ErrorAction Stop
    }
    catch {
        return Get-ADTrust -Filter * -Properties * -ErrorAction Stop |
            Where-Object {
                $_.Name -eq $TargetDomain -or
                $_.Target -eq $TargetDomain -or
                $_.DistinguishedName -like "*$TargetDomain*"
            } |
            Select-Object -First 1
    }
}

function New-AdmtServiceAccount {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][securestring]$Password
    )

    Import-Module ActiveDirectory -ErrorAction Stop

    $sam = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'SamAccountName')
    $upn = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'UserPrincipalName')
    $name = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'Name')
    $path = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'Path')
    $description = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'Description')

    if ([string]::IsNullOrWhiteSpace($sam)) {
        throw "Service account SamAccountName is required when CreateIfMissing is true."
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $sam
    }

    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = (Get-ADDomain -ErrorAction Stop).UsersContainer
    }

    if ([string]::IsNullOrWhiteSpace($upn)) {
        $upn = "$sam@$((Get-ADDomain -ErrorAction Stop).DNSRoot)"
    }

    $enabled = ConvertTo-AdmtPreparationBoolean -Value (Get-AdmtObjectProperty -InputObject $Rule -Name 'Enabled') -Default $true
    $passwordNeverExpires = ConvertTo-AdmtPreparationBoolean -Value (Get-AdmtObjectProperty -InputObject $Rule -Name 'PasswordNeverExpires') -Default $true

    $params = @{
        Name                  = $name
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        Path                  = $path
        AccountPassword       = $Password
        Enabled               = $enabled
        PasswordNeverExpires  = $passwordNeverExpires
        ChangePasswordAtLogon = $false
        ErrorAction           = 'Stop'
    }
    if (-not [string]::IsNullOrWhiteSpace($description)) {
        $params.Description = $description
    }

    if (-not $PSCmdlet.ShouldProcess($sam, "Create AD service account in $path")) {
        return $null
    }

    New-ADUser @params
    return Get-AdmtServiceAccount -Rule $Rule
}

function Set-AdmtTrustBooleanProperty {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Trust,
        [Parameter(Mandatory)][string]$ParameterName,
        [Parameter(Mandatory)][bool]$Value
    )

    $command = Get-Command Set-ADTrust -ErrorAction SilentlyContinue
    if (-not $command) {
        throw 'Set-ADTrust is not available in the ActiveDirectory module on this host.'
    }

    if (-not $command.Parameters.ContainsKey($ParameterName)) {
        throw "Set-ADTrust on this host does not expose -$ParameterName. Update RSAT/ActiveDirectory module or apply this trust setting manually."
    }

    $target = if ($Trust.Name) { [string]$Trust.Name } else { [string]$Trust.DistinguishedName }
    if ($PSCmdlet.ShouldProcess($target, "Set AD trust $ParameterName to $Value")) {
        $params = @{
            Identity    = $Trust
            ErrorAction = 'Stop'
        }
        $params[$ParameterName] = $Value
        Set-ADTrust @params
    }
}

function Test-AdmtDnsResolutionRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)]$Rule
    )

    $hostName = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'HostName')
    $recordType = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'RecordType')
    $dnsServer = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'DnsServer')
    $expectedAddresses = @(Get-AdmtObjectProperty -InputObject $Rule -Name 'ExpectedAddresses' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $severity = if (Get-AdmtObjectProperty -InputObject $Rule -Name 'Severity') { [string]$Rule.Severity } else { 'Fail' }
    $recommendation = [string](Get-AdmtObjectProperty -InputObject $Rule -Name 'Recommendation')

    if ([string]::IsNullOrWhiteSpace($hostName)) {
        return New-AdmtPreparationResult `
            -Role $Role `
            -Category 'DnsResolution' `
            -Name ([string]$Rule.Name) `
            -Status 'Manual' `
            -Severity 'Info' `
            -CurrentValue 'No host name configured' `
            -ExpectedValue 'HostName' `
            -Recommendation $recommendation
    }

    if ([string]::IsNullOrWhiteSpace($recordType)) {
        $recordType = 'A'
    }

    $answers = @()
    $errorMessage = ''

    try {
        if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
            $params = @{
                Name        = $hostName
                Type        = $recordType
                ErrorAction = 'Stop'
            }
            if (-not [string]::IsNullOrWhiteSpace($dnsServer)) {
                $params.Server = $dnsServer
            }

            $answers = @(Resolve-DnsName @params | Where-Object {
                $_.IPAddress -or $_.NameHost -or $_.NameExchange
            })
        }
        elseif ($recordType -in @('A', 'AAAA')) {
            $answers = @([System.Net.Dns]::GetHostAddresses($hostName) | ForEach-Object {
                [pscustomobject]@{ IPAddress = $_.IPAddressToString }
            })
        }
        else {
            throw "Resolve-DnsName is not available and fallback DNS lookup only supports A/AAAA records."
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    $answerValues = @($answers | ForEach-Object {
        $ipAddress = Get-AdmtObjectProperty -InputObject $_ -Name 'IPAddress'
        $nameHost = Get-AdmtObjectProperty -InputObject $_ -Name 'NameHost'
        $nameExchange = Get-AdmtObjectProperty -InputObject $_ -Name 'NameExchange'

        if ($ipAddress) { [string]$ipAddress }
        elseif ($nameHost) { [string]$nameHost }
        elseif ($nameExchange) { [string]$nameExchange }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    $missingExpected = @()
    if ($expectedAddresses.Count -gt 0) {
        $missingExpected = @($expectedAddresses | Where-Object { $answerValues -notcontains $_ })
    }

    $status = if ($answerValues.Count -gt 0 -and $missingExpected.Count -eq 0) { 'Pass' } else { 'Fail' }
    $expected = if ($expectedAddresses.Count -gt 0) { "$recordType record containing: $($expectedAddresses -join ', ')" } else { "$recordType record resolves" }
    $current = if ($answerValues.Count -gt 0) { $answerValues -join ', ' } else { '<no answer>' }
    if ($missingExpected.Count -gt 0) {
        $errorMessage = "Missing expected answer(s): $($missingExpected -join ', ')"
    }

    New-AdmtPreparationResult `
        -Role $Role `
        -Category 'DnsResolution' `
        -Name $hostName `
        -Status $status `
        -Severity $severity `
        -CurrentValue $current `
        -ExpectedValue $expected `
        -Recommendation $recommendation `
        -ErrorMessage $errorMessage
}

function ConvertTo-AdmtCimStartMode {
    [CmdletBinding()]
    param(
        [string]$StartType
    )

    switch -Regex ($StartType) {
        '^Automatic$' { return 'Auto' }
        '^Manual$' { return 'Manual' }
        '^Disabled$' { return 'Disabled' }
        default { return $StartType }
    }
}

function ConvertTo-AdmtServiceStartType {
    [CmdletBinding()]
    param(
        [string]$StartType
    )

    switch -Regex ($StartType) {
        '^Auto$' { return 'Automatic' }
        default { return $StartType }
    }
}
