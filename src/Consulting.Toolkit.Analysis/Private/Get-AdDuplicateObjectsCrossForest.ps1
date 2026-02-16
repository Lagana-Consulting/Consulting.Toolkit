function Get-AdDuplicateObjectsCrossForest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$AllUsers,

        [Parameter(Mandatory)]
        [array]$AllGroups,

        [Parameter(Mandatory)]
        [array]$AllComputers,

        [Parameter(Mandatory = $false)]
        [switch]$ExcludeBuiltIn
    )

    $builtInNames = @(
        # User accounts
        'administrator', 'guest', 'krbtgt', 'defaultaccount', 'wdagutilityaccount',

        # Core administrative groups
        'domain admins', 'enterprise admins', 'schema admins', 'administrators',
        'group policy creator owners',

        # Common domain groups
        'domain users', 'domain computers', 'domain guests', 'authenticated users', 'everyone',

        # DNS-related
        'dnsadmins', 'dnsupdateproxy',

        # Infrastructure services
        'ras and ias servers', 'allowed rodc password replication group', 'denied rodc password replication group',
        'read-only domain controllers', 'enterprise read-only domain controllers',

        # Operational groups
        'account operators', 'server operators', 'backup operators', 'print operators',
        'network configuration operators', 'replicator',

        # Legacy and compatibility
        'pre-windows 2000 compatible access', 'incoming forest trust builders',
        'performance monitor users', 'performance log users', 'event log readers',
        'distributed com users',

        # RODC and credential groups
        'key admins', 'enterprise key admins',

        # Hardened accounts and controllers
        'protected users', 'domain controllers', 'cloneable domain controllers',

        # Certificate and security
        'cert publishers', 'certificate service dcom access',

        # Remote and terminal services
        'remote desktop users', 'remote management users', 'terminal server license servers',
        'rds endpoint servers', 'rds management servers', 'rds remote access servers',

        # Storage and specialized
        'storage replica administrators', 'cryptographic operators',
        'hyper-v administrators', 'iis_iusrs',

        # Access groups
        'users', 'guests', 'windows authorization access group'
    )

    $builtInSet = @{}
    foreach ($n in $builtInNames) { $builtInSet[$n] = $true }

    function Test-IsBuiltInName {
        param([string]$Name)
        if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
        $key = $Name.Trim().ToLowerInvariant()
        return $builtInSet.ContainsKey($key)
    }

    $records = @()

    foreach ($u in @($AllUsers)) {
        if ($ExcludeBuiltIn -and (Test-IsBuiltInName -Name $u.SamAccountName)) { continue }
        $records += [pscustomobject]@{
            ObjectClass       = 'user'
            SamAccountName    = [string]$u.SamAccountName
            UserPrincipalName = [string]$u.UserPrincipalName
            Mail              = [string]$u.Mail
            DistinguishedName = [string]$u.DistinguishedName
            DomainFqdn        = [string]$u.DomainFqdn
        }
    }

    foreach ($g in @($AllGroups)) {
        if ($ExcludeBuiltIn -and (Test-IsBuiltInName -Name $g.SamAccountName)) { continue }
        $records += [pscustomobject]@{
            ObjectClass       = 'group'
            SamAccountName    = [string]$g.SamAccountName
            UserPrincipalName = ''
            Mail              = [string]$g.Mail
            DistinguishedName = [string]$g.DistinguishedName
            DomainFqdn        = [string]$g.DomainFqdn
        }
    }

    foreach ($c in @($AllComputers)) {
        if ($ExcludeBuiltIn -and (Test-IsBuiltInName -Name $c.SamAccountName)) { continue }
        $records += [pscustomobject]@{
            ObjectClass       = 'computer'
            SamAccountName    = [string]$c.SamAccountName
            UserPrincipalName = ''
            Mail              = ''
            DistinguishedName = [string]$c.DistinguishedName
            DomainFqdn        = [string]$c.DomainFqdn
        }
    }

    function New-ConflictRecord {
        param(
            [string]$ConflictType,
            [string]$ConflictValue,
            [array]$Items
        )

        $objectClasses = ($Items | Select-Object -ExpandProperty ObjectClass -Unique) -join '; '
        $domains = ($Items | Select-Object -ExpandProperty DomainFqdn -Unique) -join '; '
        $dns = ($Items | Select-Object -ExpandProperty DistinguishedName) -join ' | '

        $severity = if ($ConflictType -eq 'Mail') { 'Medium' } else { 'High' }
        $recommendation = switch ($ConflictType) {
            'SamAccountName' { 'Rename conflicting objects before migration' }
            'UserPrincipalName' { 'Resolve UPN conflicts before migration' }
            'Mail' { 'Resolve mail conflicts before migration' }
            default { 'Resolve conflicts before migration' }
        }

        [pscustomobject]@{
            ConflictType       = $ConflictType
            ConflictValue      = $ConflictValue
            ObjectClasses      = $objectClasses
            ConflictCount      = $Items.Count
            ConflictingDomains = $domains
            ConflictingDNs     = $dns
            Severity           = $severity
            Recommendation     = $recommendation
        }
    }

    $results = @()

    # SamAccountName conflicts across all object types
    $samGroups = $records |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.SamAccountName) } |
    Group-Object -Property { $_.SamAccountName.ToLowerInvariant() }

    foreach ($g in $samGroups) {
        if ($g.Count -gt 1) {
            $conflictValue = [string]($g.Group[0].SamAccountName)
            $results += New-ConflictRecord -ConflictType 'SamAccountName' -ConflictValue $conflictValue -Items $g.Group
        }
    }

    # UPN conflicts (users only)
    $upnGroups = $records |
    Where-Object { $_.ObjectClass -eq 'user' -and -not [string]::IsNullOrWhiteSpace($_.UserPrincipalName) } |
    Group-Object -Property { $_.UserPrincipalName.ToLowerInvariant() }

    foreach ($g in $upnGroups) {
        if ($g.Count -gt 1) {
            $conflictValue = [string]($g.Group[0].UserPrincipalName)
            $results += New-ConflictRecord -ConflictType 'UserPrincipalName' -ConflictValue $conflictValue -Items $g.Group
        }
    }

    # UPN local-part conflicts (users only)
    $upnLocalGroups = $records |
    Where-Object { $_.ObjectClass -eq 'user' -and -not [string]::IsNullOrWhiteSpace($_.UserPrincipalName) } |
    Group-Object -Property {
        $upn = [string]$_.UserPrincipalName
        $idx = $upn.IndexOf('@')
        if ($idx -gt 0) { $upn.Substring(0, $idx).ToLowerInvariant() } else { $upn.ToLowerInvariant() }
    }

    foreach ($g in $upnLocalGroups) {
        if ($g.Count -gt 1) {
            $conflictValue = [string]$g.Name
            $results += New-ConflictRecord -ConflictType 'UserPrincipalNameLocal' -ConflictValue $conflictValue -Items $g.Group
        }
    }

    # Mail conflicts (users + groups)
    $mailGroups = $records |
    Where-Object { $_.ObjectClass -in @('user', 'group') -and -not [string]::IsNullOrWhiteSpace($_.Mail) } |
    Group-Object -Property { $_.Mail.ToLowerInvariant() }

    foreach ($g in $mailGroups) {
        if ($g.Count -gt 1) {
            $conflictValue = [string]($g.Group[0].Mail)
            $results += New-ConflictRecord -ConflictType 'Mail' -ConflictValue $conflictValue -Items $g.Group
        }
    }

    # Mail local-part conflicts (users + groups)
    $mailLocalGroups = $records |
    Where-Object { $_.ObjectClass -in @('user', 'group') -and -not [string]::IsNullOrWhiteSpace($_.Mail) } |
    Group-Object -Property {
        $mail = [string]$_.Mail
        $idx = $mail.IndexOf('@')
        if ($idx -gt 0) { $mail.Substring(0, $idx).ToLowerInvariant() } else { $mail.ToLowerInvariant() }
    }

    foreach ($g in $mailLocalGroups) {
        if ($g.Count -gt 1) {
            $conflictValue = [string]$g.Name
            $results += New-ConflictRecord -ConflictType 'MailLocal' -ConflictValue $conflictValue -Items $g.Group
        }
    }

    return $results | Sort-Object -Property ConflictType, ConflictValue
}
