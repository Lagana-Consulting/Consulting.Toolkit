function Test-AdBuiltInGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Group
    )

    if ($null -eq $Group) {
        return $false
    }

    $sam = ''
    if ($Group.PSObject.Properties['SamAccountName']) {
        $sam = ([string]$Group.SamAccountName).Trim().ToLowerInvariant()
    }

    $dn = ''
    if ($Group.PSObject.Properties['DistinguishedName']) {
        $dn = [string]$Group.DistinguishedName
    }

    $sid = ''
    if ($Group.PSObject.Properties['SID']) {
        $sid = [string]$Group.SID
    }

    $builtInNames = @(
        'access control assistance operators',
        'account operators',
        'administrators',
        'allowed rodc password replication group',
        'backup operators',
        'certificate service dcom access',
        'cert publishers',
        'cloneable domain controllers',
        'cryptographic operators',
        'denied rodc password replication group',
        'distributed com users',
        'dnsadmins',
        'dnsupdateproxy',
        'domain admins',
        'domain computers',
        'domain controllers',
        'domain guests',
        'domain users',
        'enterprise admins',
        'enterprise key admins',
        'enterprise read-only domain controllers',
        'event log readers',
        'guests',
        'group policy creator owners',
        'hyper-v administrators',
        'iis_iusrs',
        'incoming forest trust builders',
        'key admins',
        'network configuration operators',
        'performance log users',
        'performance monitor users',
        'pre-windows 2000 compatible access',
        'print operators',
        'protected users',
        'rds endpoint servers',
        'rds management servers',
        'rds remote access servers',
        'read-only domain controllers',
        'remote desktop users',
        'remote management users',
        'replicator',
        'schema admins',
        'server operators',
        'storage replica administrators',
        'terminal server license servers',
        'users',
        'windows authorization access group'
    )

    if (-not [string]::IsNullOrWhiteSpace($sam) -and $builtInNames -contains $sam) {
        return $true
    }

    if ($dn -match '^(?i)CN=[^,]+,CN=Builtin,') {
        return $true
    }

    if ($sid -match '^S-1-5-32-') {
        return $true
    }

    if ($sid -match '-(512|513|514|515|516|517|518|519|520|521|522|525|526|527|553)$') {
        return $true
    }

    return $false
}
