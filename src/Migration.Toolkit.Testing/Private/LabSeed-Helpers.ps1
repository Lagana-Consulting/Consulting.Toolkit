function Import-AdTestingCsvSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    try {
        return @(Import-Csv -LiteralPath $Path -ErrorAction Stop)
    }
    catch {
        Write-Warning "Failed to import CSV: $Path. $($_.Exception.Message)"
        return @()
    }
}

function Get-AdTestingDiscoveryData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot
    )

    if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
        throw "Discovery run root not found: $RunRoot"
    }

    $users = New-Object System.Collections.Generic.List[object]
    $groups = New-Object System.Collections.Generic.List[object]
    $domainRoot = Join-Path $RunRoot '20_domains'
    $domainFolders = @(Get-ChildItem -LiteralPath $domainRoot -Directory -ErrorAction SilentlyContinue)

    foreach ($domainFolder in $domainFolders) {
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Identity__Users__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdTestingCsvSafe -Path $_.FullName })) {
            [void]$users.Add($row)
        }
        foreach ($row in @(Get-ChildItem -LiteralPath $domainFolder.FullName -Filter 'AD__Domain__Identity__Groups__*.csv' -File -ErrorAction SilentlyContinue | ForEach-Object { Import-AdTestingCsvSafe -Path $_.FullName })) {
            [void]$groups.Add($row)
        }
    }

    return [pscustomobject]@{
        Users  = @($users.ToArray())
        Groups = @($groups.ToArray())
    }
}

function ConvertTo-AdTestingBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes', 'y')) { return $true }
    if ($text -in @('false', '0', 'no', 'n')) { return $false }
    return $Default
}

function Get-AdTestingDomainDn {
    [CmdletBinding()]
    param()

    Import-Module ActiveDirectory -ErrorAction Stop
    return (Get-ADDomain -ErrorAction Stop).DistinguishedName
}

function ConvertTo-AdTestingSafeName {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Value,
        [string]$Fallback = 'Object',
        [int]$MaxLength = 64
    )

    $name = if ([string]::IsNullOrWhiteSpace($Value)) { $Fallback } else { $Value.Trim() }
    $name = $name -replace '[,=+<>#;"\\\/]', '_'
    $name = $name -replace '[\x00-\x1F]', ''
    $name = $name.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return $Fallback }
    if ($MaxLength -gt 0 -and $name.Length -gt $MaxLength) {
        $name = $name.Substring(0, $MaxLength).Trim()
    }
    return $name
}

function ConvertTo-AdTestingSafeDescription {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $description = $Value.Trim() -replace '[\x00-\x1F]', ' '
    if ($description.Length -gt 1024) {
        $description = $description.Substring(0, 1024).Trim()
    }

    return $description
}

function ConvertTo-AdTestingLdapFilterValue {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return $Value.Replace('\', '\5c').Replace('*', '\2a').Replace('(', '\28').Replace(')', '\29').Replace([string][char]0, '\00')
}

function Get-AdTestingSourceDomainName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Row
    )

    $domain = [string]$Row.DomainFqdn
    if (-not [string]::IsNullOrWhiteSpace($domain)) {
        return $domain.Trim().ToLowerInvariant()
    }

    $dn = [string]$Row.DistinguishedName
    $dcParts = @([regex]::Matches($dn, '(?i)(?<=DC=)[^,]+') | ForEach-Object { $_.Value })
    if ($dcParts.Count -gt 0) {
        return ($dcParts -join '.').ToLowerInvariant()
    }

    return 'unknown-domain'
}

function Get-AdTestingSourceOuPath {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$DistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
        return @()
    }

    $parts = @($DistinguishedName -split '(?<!\\),')
    if ($parts.Count -le 1) {
        return @()
    }

    $containers = New-Object System.Collections.Generic.List[string]
    foreach ($part in @($parts | Select-Object -Skip 1)) {
        if ($part -match '^(?i)(OU|CN)=(.+)$') {
            [void]$containers.Add((ConvertTo-AdTestingSafeName -Value $matches[2] -Fallback 'Container'))
            continue
        }

        if ($part -match '^(?i)DC=') {
            break
        }
    }

    $result = @($containers.ToArray())
    [array]::Reverse($result)
    return $result
}

function Ensure-AdTestingOu {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ParentDn,
        [string]$Description,
        [switch]$SkipDirectoryLookup
    )

    $safeName = ConvertTo-AdTestingSafeName -Value $Name -Fallback 'OU'
    $targetDn = "OU=$safeName,$ParentDn"
    if ($SkipDirectoryLookup) {
        return $targetDn
    }

    $existing = $null
    try {
        $existing = Get-ADOrganizationalUnit -LDAPFilter "(ou=$safeName)" -SearchBase $ParentDn -SearchScope OneLevel -ErrorAction Stop | Select-Object -First 1
    }
    catch {
        if (-not $WhatIfPreference) {
            throw
        }
    }

    if ($existing) {
        return $existing.DistinguishedName
    }

    if ($PSCmdlet.ShouldProcess($targetDn, 'Create staging OU')) {
        New-ADOrganizationalUnit -Name $safeName -Path $ParentDn -Description $Description -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop | Out-Null
    }

    return $targetDn
}

function Resolve-AdTestingObjectPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$StagingBaseDn,
        [switch]$PreserveSourceOuPath,
        [switch]$SkipDirectoryLookup
    )

    $domainName = Get-AdTestingSourceDomainName -Row $Row
    $currentDn = Ensure-AdTestingOu -Name $domainName -ParentDn $StagingBaseDn -Description 'Migration lab source-domain staging root' -SkipDirectoryLookup:$SkipDirectoryLookup -WhatIf:$WhatIfPreference

    if ($PreserveSourceOuPath) {
        foreach ($ouName in @(Get-AdTestingSourceOuPath -DistinguishedName ([string]$Row.DistinguishedName))) {
            $currentDn = Ensure-AdTestingOu -Name $ouName -ParentDn $currentDn -Description 'Migration lab source OU path' -SkipDirectoryLookup:$SkipDirectoryLookup -WhatIf:$WhatIfPreference
        }
    }

    return $currentDn
}

function Get-AdTestingUniqueSam {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [ValidateSet('User', 'Group')][string]$ObjectType = 'User'
    )

    $clean = ($SamAccountName -replace '[\\\/\[\]:;|=,+*?<>"]', '_').Trim()
    $clean = $clean -replace '[\x00-\x1F]', ''
    if ([string]::IsNullOrWhiteSpace($clean)) {
        $clean = if ($ObjectType -eq 'Group') { 'LabGroup' } else { 'LabUser' }
    }

    if ($ObjectType -eq 'User' -and $clean.Length -gt 20) {
        $clean = $clean.Substring(0, 20)
    }

    return $clean
}

function New-AdTestingActionRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ObjectType,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][string]$Action,
        [string]$Path = '',
        [string]$DistinguishedName = '',
        [string]$Message = '',
        [string]$SourceDistinguishedName = ''
    )

    return [pscustomobject]@{
        ObjectType        = $ObjectType
        Name              = $Name
        SamAccountName    = $SamAccountName
        Action            = $Action
        Path              = $Path
        DistinguishedName = $DistinguishedName
        SourceDistinguishedName = $SourceDistinguishedName
        Message           = $Message
    }
}
