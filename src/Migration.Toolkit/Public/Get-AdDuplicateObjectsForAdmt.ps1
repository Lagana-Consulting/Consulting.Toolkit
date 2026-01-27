function Get-AdDuplicateObjectsForAdmt {
    param(
        [array]$AllUsers = @(),
        [array]$AllComputers = @(),
        [array]$AllGroups = @()
    )

    $results = @()

    # Early exit if all empty
    if (@($AllUsers).Count -eq 0 -and @($AllComputers).Count -eq 0 -and @($AllGroups).Count -eq 0) {
        return @()
    }

    # Define built-in accounts to exclude (exist in all AD environments)
    $builtInAccounts = @(
        'Administrator', 'Guest', 'krbtgt', 'DefaultAccount', 'WDAGUtilityAccount',
        'Domain Admins', 'Domain Users', 'Domain Guests', 'Domain Computers', 'Domain Controllers',
        'Schema Admins', 'Enterprise Admins', 'Cert Publishers', 'Group Policy Creator Owners',
        'RAS and IAS Servers', 'Server Operators', 'Account Operators', 'Pre-Windows 2000 Compatible Access',
        'Incoming Forest Trust Builders', 'Windows Authorization Access Group', 'Terminal Server License Servers',
        'Allowed RODC Password Replication Group', 'Denied RODC Password Replication Group',
        'Read-only Domain Controllers', 'Enterprise Read-only Domain Controllers', 'Cloneable Domain Controllers',
        'Protected Users', 'Key Admins', 'Enterprise Key Admins', 'DnsAdmins', 'DnsUpdateProxy',
        'DHCP Administrators', 'DHCP Users', 'Print Operators', 'Backup Operators', 'Replicator',
        'Network Configuration Operators', 'Performance Monitor Users', 'Performance Log Users',
        'Distributed COM Users', 'IIS_IUSRS', 'Cryptographic Operators', 'Event Log Readers',
        'Certificate Service DCOM Access', 'RDS Remote Access Servers', 'RDS Endpoint Servers',
        'RDS Management Servers', 'Hyper-V Administrators', 'Access Control Assistance Operators',
        'Remote Management Users', 'Storage Replica Administrators'
    )

    # Check for duplicate sAMAccountNames across domains
    # Add ObjectClass property to each object based on which array it came from
    # Filter out built-in accounts
    $allObjects = @()
    $allObjects += $AllUsers | Where-Object { $_.SamAccountName -notin $builtInAccounts } | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name ObjectClass -Value 'user' -Force; $_ }
    $allObjects += $AllComputers | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name ObjectClass -Value 'computer' -Force; $_ }
    $allObjects += $AllGroups | Where-Object { $_.SamAccountName -notin $builtInAccounts } | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name ObjectClass -Value 'group' -Force; $_ }

    $samDuplicates = $allObjects | Group-Object -Property SamAccountName | Where-Object { $_.Count -gt 1 }

    foreach ($dup in $samDuplicates) {
        $conflictingDomains = ($dup.Group | Select-Object -ExpandProperty DomainFqdn -Unique) -join '; '
        $conflictingDNs = ($dup.Group | Select-Object -ExpandProperty DistinguishedName) -join ' | '
        $objectClasses = ($dup.Group | Select-Object -ExpandProperty ObjectClass -Unique) -join '; '

        $results += [pscustomobject]@{
            ConflictType       = 'SamAccountName'
            ConflictValue      = $dup.Name
            ObjectClasses      = $objectClasses
            ConflictCount      = $dup.Count
            ConflictingDomains = $conflictingDomains
            ConflictingDNs     = $conflictingDNs
            Severity           = 'High'
            Recommendation     = 'Rename before ADMT migration to prevent conflicts'
        }
    }

    # Check for duplicate UPNs (users only)
    $upnDuplicates = $AllUsers | Where-Object { $_.UserPrincipalName } |
    Group-Object -Property UserPrincipalName | Where-Object { $_.Count -gt 1 }

    foreach ($dup in $upnDuplicates) {
        $conflictingDomains = ($dup.Group | Select-Object -ExpandProperty DomainFqdn -Unique) -join '; '
        $conflictingDNs = ($dup.Group | Select-Object -ExpandProperty DistinguishedName) -join ' | '

        $results += [pscustomobject]@{
            ConflictType       = 'UserPrincipalName'
            ConflictValue      = $dup.Name
            ObjectClasses      = 'user'
            ConflictCount      = $dup.Count
            ConflictingDomains = $conflictingDomains
            ConflictingDNs     = $conflictingDNs
            Severity           = 'High'
            Recommendation     = 'Change UPN before migration to prevent authentication issues'
        }
    }

    # Check for duplicate mail attributes (if present)
    $mailDuplicates = $AllUsers | Where-Object { $_.PSObject.Properties['Mail'] -and $_.Mail } |
    Group-Object -Property Mail | Where-Object { $_.Count -gt 1 }

    foreach ($dup in $mailDuplicates) {
        $conflictingDomains = ($dup.Group | Select-Object -ExpandProperty DomainFqdn -Unique) -join '; '
        $conflictingDNs = ($dup.Group | Select-Object -ExpandProperty DistinguishedName) -join ' | '

        $results += [pscustomobject]@{
            ConflictType       = 'Mail'
            ConflictValue      = $dup.Name
            ObjectClasses      = 'user'
            ConflictCount      = $dup.Count
            ConflictingDomains = $conflictingDomains
            ConflictingDNs     = $conflictingDNs
            Severity           = 'Medium'
            Recommendation     = 'Review for Exchange/email conflicts post-migration'
        }
    }

    return $results
}
