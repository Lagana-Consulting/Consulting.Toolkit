function Get-AdUpnSuffix {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$UserPrincipalName
    )

    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) { return $null }

    $at = $UserPrincipalName.LastIndexOf('@')
    if ($at -lt 0 -or $at -eq ($UserPrincipalName.Length - 1)) { return $null }

    return $UserPrincipalName.Substring($at + 1).ToLowerInvariant()
}

function Test-AdNonRoutableSuffix {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Suffix
    )

    if ([string]::IsNullOrWhiteSpace($Suffix)) { return $true }

    $s = $Suffix.Trim().ToLowerInvariant()

    # Common internal / non-routable patterns
    if ($s -match '\.local$') { return $true }
    if ($s -match '\.internal$') { return $true }
    if ($s -match '\.lan$') { return $true }
    if ($s -match '\.corp$') { return $true }
    if ($s -match '\.home$') { return $true }
    if ($s -match '\.intra$') { return $true }

    return $false
}

function ConvertFrom-AdFileTime {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$FileTime
    )

    if ($null -eq $FileTime) { return $null }

    try {
        # lastLogonTimestamp can come back as Int64, string, or large integer
        [int64]$ft = [int64]$FileTime
        if ($ft -le 0) { return $null }
        return [DateTime]::FromFileTimeUtc($ft)
    }
    catch {
        return $null
    }
}

function Get-AdDaysSince {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $DateUtc,

        $Now = (Get-Date).ToUniversalTime()
    )

    if ($null -eq $DateUtc) { return $null }

    $n = if ($Now) { $Now.ToUniversalTime() } else { (Get-Date).ToUniversalTime() }
    $d = $DateUtc.ToUniversalTime()

    # Avoid negative days due to clock skew
    $days = ($n - $d).TotalDays
    if ($days -lt 0) { $days = 0 }

    return [int][math]::Floor($days)
}

function Convert-AdEncryptionTypes {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$EncryptionTypeValue
    )

    if ($null -eq $EncryptionTypeValue -or [string]::IsNullOrWhiteSpace([string]$EncryptionTypeValue)) {
        return @()
    }

    [int]$v = 0
    try { $v = [int]$EncryptionTypeValue } catch { return @() }

    $types = New-Object System.Collections.Generic.List[string]

    # Bits per Microsoft convention (common)
    if (($v -band 0x01) -ne 0) { $types.Add('DES_CBC_CRC') }
    if (($v -band 0x02) -ne 0) { $types.Add('DES_CBC_MD5') }
    if (($v -band 0x04) -ne 0) { $types.Add('RC4_HMAC') }
    if (($v -band 0x08) -ne 0) { $types.Add('AES128_HMAC_SHA1') }
    if (($v -band 0x10) -ne 0) { $types.Add('AES256_HMAC_SHA1') }

    # Some environments may show this bit; treat as info
    if (($v -band 0x20) -ne 0) { $types.Add('FAST_SUPPORTED') }

    return $types.ToArray()
}

function Get-AdEncryptionRisk {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$EncryptionTypeValue
    )

    $types = Convert-AdEncryptionTypes -EncryptionTypeValue $EncryptionTypeValue

    if (-not $types -or $types.Count -eq 0) {
        # Not set often means "defaults", but defaults vary. Keep neutral.
        return 'Unknown'
    }

    $hasAes = ($types -contains 'AES128_HMAC_SHA1' -or $types -contains 'AES256_HMAC_SHA1')
    $hasRc4 = ($types -contains 'RC4_HMAC')
    $hasDes = ($types -contains 'DES_CBC_CRC' -or $types -contains 'DES_CBC_MD5')

    if ($hasDes) { return 'High' }      # DES is legacy/weak
    if ($hasRc4 -and -not $hasAes) { return 'Medium' }  # RC4 only
    if ($hasAes) { return 'Low' }

    return 'Unknown'
}

function Get-AdAdUsers {
    <#
  .SYNOPSIS
  Retrieves all user accounts from a domain with migration-relevant properties.

  .DESCRIPTION
  Enumerates all user accounts with comprehensive properties for migration assessment:
  - Account status (enabled, last logon, password age)
  - UPN suffix validation and routability
  - Privilege indicators (adminCount)
  - SID history count
  - SPN count and encryption types
  - Risk assessment (weak encryption)

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext. Required.

  .PARAMETER Now
  Reference timestamp for age calculations. Defaults to current date/time.
  Used for calculating LastLogonDays and PasswordAgeDays.

  .PARAMETER KnownUpnSuffixSet
  Hashtable of known UPN suffixes from Get-AdKnownUpnSuffixes -AsHashSet.
  Used to flag unknown suffixes. Optional.

  .EXAMPLE
  $ctx = Get-AdAdDomainContext -DomainFqdn "contoso.com"
  $users = Get-AdAdUsers -DomainContext $ctx

  Gets all users in contoso.com with standard properties.

  .EXAMPLE
  $knownSuffixes = Get-AdKnownUpnSuffixes -AsHashSet
  $users = Get-AdAdUsers -DomainContext $ctx -KnownUpnSuffixSet $knownSuffixes
  $users | Where-Object { -not $_.IsKnownUpnSuffix } | Select-Object SamAccountName, UserPrincipalName

  Finds users with unknown UPN suffixes.

  .EXAMPLE
  $users | Where-Object { $_.EncryptionRisk -eq 'High' }

  Identifies users with weak encryption types (DES-only or RC4-only).

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  PSCustomObject[]. User objects with properties including:
  - Account: SamAccountName, UPN, Mail, Enabled
  - Timestamps: WhenCreated, LastLogonDays, PasswordAgeDays
  - Risk: AdminCount, SidHistoryCount, EncryptionRisk, IsNonRoutableUpn
  - SPNs: SpnCount, EncryptionTypes

  .NOTES
  Requires Active Directory PowerShell module.
  LastLogonTimestamp is replicated (not real-time).
  Use KnownUpnSuffixSet for cross-forest UPN validation.

  .LINK
  Get-AdAdDomainContext
  Get-AdKnownUpnSuffixes
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        $Now = (Get-Date),

        # For routability flags – pass the set from Get-AdKnownUpnSuffixes -AsHashSet
        [hashtable]$KnownUpnSuffixSet
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADUser missing)."
    }

    $domain = [string]$DomainContext.DomainFqdn
    $server = [string]$DomainContext.Server
    $nowUtc = $Now.ToUniversalTime()

    $props = @(
        'Enabled', 'UserPrincipalName', 'Mail', 'whenCreated', 'whenChanged',
        'LastLogonTimestamp', 'PasswordLastSet', 'adminCount', 'SIDHistory',
        'ServicePrincipalName', 'msDS-SupportedEncryptionTypes', 'Description'
    )

    $users = @()
    try {
        $users = @(Get-ADUser -Filter * -Server $server -Properties $props -ErrorAction Stop |
            Sort-Object SamAccountName)
    }
    catch {
        # Try without server parameter as fallback
        try {
            $users = @(Get-ADUser -Filter * -Properties $props -ErrorAction Stop |
                Sort-Object SamAccountName)
        }
        catch {
            throw "Failed to enumerate users for $domain. $($_.Exception.Message)"
        }
    }

    foreach ($u in $users) {
        $upnSuffix = Get-AdUpnSuffix -UserPrincipalName $u.UserPrincipalName
        $isNonRoutable = if ($upnSuffix) { Test-AdNonRoutableSuffix -Suffix $upnSuffix } else { $true }

        $isKnownSuffix = $null
        if ($KnownUpnSuffixSet -and $upnSuffix) {
            $isKnownSuffix = [bool]$KnownUpnSuffixSet.ContainsKey($upnSuffix)
        }

        $lltUtc = ConvertFrom-AdFileTime -FileTime $u.LastLogonTimestamp
        $lastLogonDays = Get-AdDaysSince -DateUtc $lltUtc -Now $nowUtc

        $pwdUtc = if ($u.PasswordLastSet) { ([datetime]$u.PasswordLastSet).ToUniversalTime() } else { $null }
        $passwordAgeDays = Get-AdDaysSince -DateUtc $pwdUtc -Now $nowUtc

        $sidHistoryCount = @($u.SIDHistory).Count
        $spnCount = @($u.ServicePrincipalName).Count

        # Handle msDS-SupportedEncryptionTypes safely (may not exist in older domains or on all objects)
        $encTypesValue = if ($u.PSObject.Properties['msDS-SupportedEncryptionTypes']) { $u.'msDS-SupportedEncryptionTypes' } else { $null }
        $encTypes = Convert-AdEncryptionTypes -EncryptionTypeValue $encTypesValue
        $encRisk = Get-AdEncryptionRisk    -EncryptionTypeValue $encTypesValue

        [pscustomobject]@{
            DomainFqdn                   = $domain
            SamAccountName               = [string]$u.SamAccountName
            Name                         = [string]$u.Name
            DistinguishedName            = [string]$u.DistinguishedName
            Enabled                      = [bool]$u.Enabled
            UserPrincipalName            = [string]$u.UserPrincipalName
            Mail                         = [string]$u.Mail
            UPNSuffix                    = $upnSuffix
            IsKnownUpnSuffix             = $isKnownSuffix
            IsNonRoutableUpnSuffix       = [bool]$isNonRoutable
            WhenCreated                  = $u.whenCreated
            WhenChanged                  = $u.whenChanged

            LastLogonTimestampUtc        = $lltUtc
            LastLogonDays                = $lastLogonDays

            PasswordLastSetUtc           = $pwdUtc
            PasswordAgeDays              = $passwordAgeDays

            AdminCount                   = [int]($u.adminCount -as [int])
            SidHistoryCount              = [int]$sidHistoryCount
            SPNCount                     = [int]$spnCount

            MsDsSupportedEncryptionTypes = $encTypesValue
            EncryptionTypes              = ($encTypes -join ';')
            EncryptionRisk               = $encRisk

            Description                  = [string]$u.Description
        }
    }
}
