function Get-LcSchemaDefinitions {
  [CmdletBinding()]
  param()

  # Return: hashtable of SchemaName -> array of column definition objects
  # Each column def has: Column, Type, Description, Example, Notes

  $schemas = @{}

  # Forest Summary
  $schemas['Forest_Summary'] = @(
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'AD forest DNS name'; Example = 'contoso.com'; Notes = 'Key identifier' }
    [pscustomobject]@{ Column = 'RootDomain'; Type = 'string'; Description = 'Root domain in forest'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ForestMode'; Type = 'string'; Description = 'Forest functional level'; Example = 'Windows2016Forest'; Notes = 'Migration prerequisite' }
    [pscustomobject]@{ Column = 'Domains'; Type = 'string'; Description = 'Semicolon-delimited list of domains'; Example = 'contoso.com;child.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainCount'; Type = 'int'; Description = 'Count of domains in forest'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'UPNSuffixes'; Type = 'string'; Description = 'Semicolon-delimited list of UPN suffixes'; Example = 'contoso.com;contoso.net'; Notes = 'Use for UPN routability checks' }
    [pscustomobject]@{ Column = 'UPNSuffixCount'; Type = 'int'; Description = 'Count of UPN suffixes'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'SchemaMaster'; Type = 'string'; Description = 'Schema master FSMO holder'; Example = 'dc1.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainNamingMaster'; Type = 'string'; Description = 'Domain naming master FSMO holder'; Example = 'dc1.contoso.com'; Notes = '' }
  )

  # Forest UPN Suffixes
  $schemas['Forest_UPNSuffixes'] = @(
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'Forest name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Suffix'; Type = 'string'; Description = 'UPN suffix'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'IsKnownSuffix'; Type = 'bool'; Description = 'Is a known/routable suffix'; Example = 'True'; Notes = 'Used for cloud sync assessment' }
    [pscustomobject]@{ Column = 'IsNonRoutable'; Type = 'bool'; Description = 'Is a non-routable (private) suffix'; Example = 'False'; Notes = 'Risk if True' }
  )

  # Domain Summary
  $schemas['Domain_Summary'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainDn'; Type = 'string'; Description = 'Domain distinguished name'; Example = 'DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'NetBIOSName'; Type = 'string'; Description = 'NetBIOS domain name'; Example = 'CONTOSO'; Notes = 'Legacy compatibility' }
    [pscustomobject]@{ Column = 'DomainMode'; Type = 'string'; Description = 'Domain functional level'; Example = 'Windows2016Domain'; Notes = 'Migration prerequisite' }
    [pscustomobject]@{ Column = 'PdcEmulator'; Type = 'string'; Description = 'PDC emulator FSMO holder'; Example = 'dc1.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'RidMaster'; Type = 'string'; Description = 'RID master FSMO holder'; Example = 'dc1.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'InfrastructureMaster'; Type = 'string'; Description = 'Infrastructure master FSMO holder'; Example = 'dc1.contoso.com'; Notes = '' }
  )

  # Users (Identity)
  $schemas['Users'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'Logon name (pre-Windows 2000)'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Display name'; Example = 'Jane Doe'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD distinguished name'; Example = 'CN=Jane Doe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Account enabled'; Example = 'True'; Notes = 'Scope reduction if False' }
    [pscustomobject]@{ Column = 'UserPrincipalName'; Type = 'string'; Description = 'UPN'; Example = 'jdoe@contoso.com'; Notes = 'Used for SSO/cloud' }
    [pscustomobject]@{ Column = 'Mail'; Type = 'string'; Description = 'Mail attribute (SMTP address)'; Example = 'jdoe@contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'UPNSuffix'; Type = 'string'; Description = 'UPN suffix extracted from UPN'; Example = 'contoso.com'; Notes = 'Risk if non-routable' }
    [pscustomobject]@{ Column = 'IsKnownUpnSuffix'; Type = 'bool'; Description = 'UPN suffix is known/registered'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'IsNonRoutableUpnSuffix'; Type = 'bool'; Description = 'UPN suffix is non-routable'; Example = 'False'; Notes = 'True indicates cloud sync risk' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Object creation time'; Example = '2022-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Object last changed'; Example = '2025-12-31'; Notes = '' }
    [pscustomobject]@{ Column = 'LastLogonTimestampUtc'; Type = 'datetime'; Description = 'Last logon timestamp (replicated, UTC)'; Example = '2025-06-01T10:30:00Z'; Notes = 'Used for staleness' }
    [pscustomobject]@{ Column = 'LastLogonDays'; Type = 'int'; Description = 'Days since last logon'; Example = '45'; Notes = 'Stale if > 90' }
    [pscustomobject]@{ Column = 'PasswordLastSetUtc'; Type = 'datetime'; Description = 'Password last set time (UTC)'; Example = '2025-01-01T09:00:00Z'; Notes = 'Stale password risk' }
    [pscustomobject]@{ Column = 'PasswordAgeDays'; Type = 'int'; Description = 'Password age in days'; Example = '20'; Notes = 'Policy compliance check' }
    [pscustomobject]@{ Column = 'AdminCount'; Type = 'int'; Description = 'adminCount attribute value'; Example = '1'; Notes = '1 indicates historically protected/admin' }
    [pscustomobject]@{ Column = 'SidHistoryCount'; Type = 'int'; Description = 'Count of SIDHistory values'; Example = '0'; Notes = 'Impacts trust/migration duration' }
    [pscustomobject]@{ Column = 'SPNCount'; Type = 'int'; Description = 'Count of service principal names'; Example = '1'; Notes = 'Kerberos/app dependency' }
    [pscustomobject]@{ Column = 'MsDsSupportedEncryptionTypes'; Type = 'int'; Description = 'Kerberos encryption bitmask'; Example = '28'; Notes = 'Explicitly-set only' }
    [pscustomobject]@{ Column = 'EncryptionTypes'; Type = 'string'; Description = 'Semicolon list of encryption types'; Example = 'RC4-HMAC;AES256-CTS-HMAC-SHA1-96'; Notes = '' }
    [pscustomobject]@{ Column = 'EncryptionRisk'; Type = 'string'; Description = 'Encryption risk level'; Example = 'Medium'; Notes = 'DES/RC4 = High, AES-only = Low' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description field'; Example = 'Service account for app X'; Notes = '' }
  )

  # Computers (Identity)
  $schemas['Computers'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Computer name'; Example = 'PC-001'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'Computer SAM (ends with $)'; Example = 'PC-001$'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD distinguished name'; Example = 'CN=PC-001,CN=Computers,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Computer account enabled'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'DnsHostName'; Type = 'string'; Description = 'DNS host name'; Example = 'pc-001.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'OperatingSystem'; Type = 'string'; Description = 'OS name'; Example = 'Windows 10 Enterprise'; Notes = 'Device migration planning' }
    [pscustomobject]@{ Column = 'OperatingSystemVersion'; Type = 'string'; Description = 'OS version'; Example = '10.0 (19045)'; Notes = '' }
    [pscustomobject]@{ Column = 'IsServer'; Type = 'bool'; Description = 'Is a server OS'; Example = 'False'; Notes = 'Derived from OperatingSystem' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Object creation time'; Example = '2021-05-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Object last changed'; Example = '2025-12-31'; Notes = '' }
    [pscustomobject]@{ Column = 'LastLogonTimestampUtc'; Type = 'datetime'; Description = 'Last logon timestamp (replicated, UTC)'; Example = '2025-10-01T14:00:00Z'; Notes = 'Used for staleness' }
    [pscustomobject]@{ Column = 'LastLogonDays'; Type = 'int'; Description = 'Days since last logon'; Example = '15'; Notes = 'Stale if > 90' }
    [pscustomobject]@{ Column = 'SPNCount'; Type = 'int'; Description = 'Count of service principal names'; Example = '5'; Notes = 'Often true for servers' }
    [pscustomobject]@{ Column = 'MsDsSupportedEncryptionTypes'; Type = 'int'; Description = 'Kerberos encryption bitmask'; Example = '24'; Notes = 'Explicitly-set only' }
    [pscustomobject]@{ Column = 'EncryptionTypes'; Type = 'string'; Description = 'Semicolon list of encryption types'; Example = 'AES128-CTS-HMAC-SHA1-96;AES256-CTS-HMAC-SHA1-96'; Notes = '' }
    [pscustomobject]@{ Column = 'EncryptionRisk'; Type = 'string'; Description = 'Encryption risk level'; Example = 'Low'; Notes = 'DES/RC4 = High, AES-only = Low' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description field'; Example = 'Finance workstation'; Notes = '' }
  )

  # Groups (Identity)
  $schemas['Groups'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Group name'; Example = 'Domain Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = 'Domain Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD distinguished name'; Example = 'CN=Domain Admins,CN=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupCategory'; Type = 'string'; Description = 'Group category'; Example = 'Security'; Notes = 'Security or Distribution' }
    [pscustomobject]@{ Column = 'GroupScope'; Type = 'string'; Description = 'Group scope'; Example = 'Global'; Notes = 'DomainLocal, Global, or Universal' }
    [pscustomobject]@{ Column = 'Mail'; Type = 'string'; Description = 'Mail attribute'; Example = 'admins@contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Object creation time'; Example = '2020-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Object last changed'; Example = '2025-11-15'; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description field'; Example = 'Administrative group'; Notes = '' }
  )

  # SPNs
  $schemas['SPNs'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = 'sqlsvc'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'Object class'; Example = 'user'; Notes = 'user or computer' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD distinguished name'; Example = 'CN=sqlsvc,OU=ServiceAccounts,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'ServicePrincipalName'; Type = 'string'; Description = 'Service principal name'; Example = 'MSSQLSvc/sql.contoso.com:1433'; Notes = 'Kerberos service identifier' }
  )

  # Privileged Accounts
  $schemas['PrivilegedAccounts'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Display name'; Example = 'Jane Doe'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD distinguished name'; Example = 'CN=Jane Doe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'Object class'; Example = 'user'; Notes = 'user or computer' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Enabled status'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'PrivilegeGroups'; Type = 'string'; Description = 'Semicolon-separated privileged group memberships'; Example = 'Domain Admins;Administrators'; Notes = 'Derived by recursive group membership + adminCount' }
  )

  # Assessment Summary
  $schemas['Assessment_Summary'] = @(
    [pscustomobject]@{ Column = 'RunTimestamp'; Type = 'datetime'; Description = 'Timestamp of assessment run'; Example = '1/12/2026 1:01:56 PM'; Notes = '' }
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'Forest name'; Example = 'SOURCELAB.COM'; Notes = '' }
    [pscustomobject]@{ Column = 'ForestRootDomain'; Type = 'string'; Description = 'Forest root domain'; Example = 'SOURCELAB.COM'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainsCount'; Type = 'int'; Description = 'Number of domains'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'UsersTotal'; Type = 'int'; Description = 'Total user count'; Example = '22'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupsTotal'; Type = 'int'; Description = 'Total group count'; Example = '98'; Notes = '' }
    [pscustomobject]@{ Column = 'ComputersTotal'; Type = 'int'; Description = 'Total computer count'; Example = '3'; Notes = '' }
    [pscustomobject]@{ Column = 'UsersStaleCount'; Type = 'int'; Description = 'Stale user count (>180d)'; Example = '1'; Notes = 'Cleanup candidate' }
    [pscustomobject]@{ Column = 'UsersStalePct'; Type = 'decimal'; Description = 'Stale user percentage'; Example = '4.55'; Notes = '' }
    [pscustomobject]@{ Column = 'ComputersStaleCount'; Type = 'int'; Description = 'Stale computer count (>90d)'; Example = '0'; Notes = 'Cleanup candidate' }
    [pscustomobject]@{ Column = 'ComputersStalePct'; Type = 'decimal'; Description = 'Stale computer percentage'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'UsersSIDHistoryCount'; Type = 'int'; Description = 'Users with SID history'; Example = '0'; Notes = 'Migration complexity' }
    [pscustomobject]@{ Column = 'UsersSIDHistoryPct'; Type = 'decimal'; Description = 'Users with SID history percentage'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'UsersNonRoutableUPNCount'; Type = 'int'; Description = 'Users with non-routable UPN suffix'; Example = '13'; Notes = 'Cloud sync blocker' }
    [pscustomobject]@{ Column = 'UsersNonRoutableUPNPct'; Type = 'decimal'; Description = 'Non-routable UPN percentage'; Example = '59.09'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectsRC4OnlyCount'; Type = 'int'; Description = 'Objects with RC4-only encryption'; Example = '0'; Notes = 'Security risk' }
    [pscustomobject]@{ Column = 'ObjectsRC4OnlyPct'; Type = 'decimal'; Description = 'RC4-only percentage'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'PrivilegedAccountsCount'; Type = 'int'; Description = 'Privileged account count'; Example = '10'; Notes = 'Security surface area' }
    [pscustomobject]@{ Column = 'EmptyGroupsCount'; Type = 'int'; Description = 'Groups with zero members'; Example = '5'; Notes = 'Cleanup candidate' }
    [pscustomobject]@{ Column = 'DuplicateSpnsCount'; Type = 'int'; Description = 'Duplicate SPN conflicts'; Example = '0'; Notes = 'Kerberos failure risk' }
    [pscustomobject]@{ Column = 'WeakPasswordPoliciesCount'; Type = 'int'; Description = 'Policies with 3+ weaknesses'; Example = '1'; Notes = 'Security risk' }
    [pscustomobject]@{ Column = 'HighDepthGroupsCount'; Type = 'int'; Description = 'Groups nested >=5 levels'; Example = '3'; Notes = 'Token bloat risk' }
    [pscustomobject]@{ Column = 'HighDepthOUsCount'; Type = 'int'; Description = 'OUs at depth >=5'; Example = '2'; Notes = 'Complexity indicator' }
    [pscustomobject]@{ Column = 'CrossDomainDependenciesCount'; Type = 'int'; Description = 'Groups with cross-domain members'; Example = '7'; Notes = 'Migration dependency' }
    [pscustomobject]@{ Column = 'DisabledUsersCount'; Type = 'int'; Description = 'Disabled user accounts'; Example = '12'; Notes = 'Cleanup candidate' }
    [pscustomobject]@{ Column = 'DisabledComputersCount'; Type = 'int'; Description = 'Disabled computer accounts'; Example = '8'; Notes = 'Cleanup candidate' }
    [pscustomobject]@{ Column = 'AdminSdHolderImpactCount'; Type = 'int'; Description = 'Objects with adminCount=1'; Example = '15'; Notes = 'ACL inheritance disabled' }
    [pscustomobject]@{ Column = 'FsmoUnavailableCount'; Type = 'int'; Description = 'Unavailable FSMO role holders'; Example = '0'; Notes = 'Critical infrastructure issue' }
    [pscustomobject]@{ Column = 'HighCostSiteLinksCount'; Type = 'int'; Description = 'Site links with cost >500'; Example = '1'; Notes = 'Replication efficiency' }
    [pscustomobject]@{ Column = 'LowTombstoneLifetimeCount'; Type = 'int'; Description = 'Tombstone lifetime <180d'; Example = '0'; Notes = 'Replication health risk' }
    [pscustomobject]@{ Column = 'TopServiceTypesCount'; Type = 'int'; Description = 'Count of top service types analyzed'; Example = '10'; Notes = 'Service dependency insight' }
  )

  # Migration Risk Flags
  $schemas['Migration_RiskFlags'] = @(
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'Object type'; Example = 'user'; Notes = 'user or computer' }
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD distinguished name'; Example = 'CN=jdoe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'UserPrincipalName'; Type = 'string'; Description = 'UPN (users only)'; Example = 'jdoe@contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Flags'; Type = 'string'; Description = 'Semicolon-separated risk flags'; Example = 'UPN_NonRoutableSuffix;PasswordNeverExpires'; Notes = 'Migration blockers/warnings' }
  )

  # Migration Risk Flags Summary
  $schemas['Migration_RiskFlags_Summary'] = @(
    [pscustomobject]@{ Column = 'Flag'; Type = 'string'; Description = 'Risk flag name'; Example = 'PasswordNeverExpires'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'Object type'; Example = 'user'; Notes = 'user or computer' }
    [pscustomobject]@{ Column = 'Count'; Type = 'int'; Description = 'Count of objects with this flag'; Example = '15'; Notes = '' }
  )

  # Certificate Services Inventory
  $schemas['CertificateServices_Inventory'] = @(
    [pscustomobject]@{ Column = 'ItemType'; Type = 'string'; Description = 'PKI component type'; Example = 'EnterpriseCA'; Notes = 'CertificateTemplate, EnterpriseCA, or NTAuthStore' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Object name'; Example = 'ContosoRootCA'; Notes = '' }
    [pscustomobject]@{ Column = 'DisplayName'; Type = 'string'; Description = 'Display name'; Example = 'Contoso Root CA'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectDN'; Type = 'string'; Description = 'Distinguished name'; Example = 'CN=ContosoRootCA,CN=Enrollment Services,...'; Notes = '' }
    [pscustomobject]@{ Column = 'Details'; Type = 'string'; Description = 'Additional details'; Example = 'Host: dc01.contoso.com'; Notes = 'OID, hostname, or certificate count' }
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'Forest name'; Example = 'contoso.com'; Notes = '' }
  )

  # DNS Zone Inventory
  $schemas['DnsZone_Inventory'] = @(
    [pscustomobject]@{ Column = 'ZoneName'; Type = 'string'; Description = 'DNS zone name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Scope'; Type = 'string'; Description = 'Replication scope'; Example = 'Domain'; Notes = 'Forest or Domain' }
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DN'; Type = 'string'; Description = 'Distinguished name'; Example = 'DC=contoso.com,CN=MicrosoftDNS,...'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Creation timestamp'; Example = '1/1/2020 12:00:00 AM'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Last modified timestamp'; Example = '1/15/2026 3:45:00 PM'; Notes = '' }
    [pscustomobject]@{ Column = 'IntegrationType'; Type = 'string'; Description = 'Integration type'; Example = 'AD-Integrated'; Notes = '' }
  )

  # DHCP Scope Analysis
  $schemas['Dhcp_ScopeAnalysis'] = @(
    [pscustomobject]@{ Column = 'DhcpServerName'; Type = 'string'; Description = 'DHCP server hostname'; Example = 'dhcp01.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DN'; Type = 'string'; Description = 'Distinguished name'; Example = 'CN=dhcp01.contoso.com,...'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Authorization status'; Example = 'Authorized'; Notes = 'Authorized or No Authorized Servers' }
    [pscustomobject]@{ Column = 'Notes'; Type = 'string'; Description = 'Additional notes'; Example = 'Scope details require DHCP module'; Notes = '' }
  )

  # SYSVOL Size Analysis
  $schemas['Sysvol_SizeAnalysis'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SysvolPath'; Type = 'string'; Description = 'SYSVOL UNC path'; Example = '\\contoso.com\SYSVOL\contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SizeGB'; Type = 'decimal'; Description = 'Total size in GB'; Example = '2.35'; Notes = '' }
    [pscustomobject]@{ Column = 'GpoFolderCount'; Type = 'int'; Description = 'Count of GPO folders'; Example = '45'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Health status'; Example = 'Warning'; Notes = 'OK, Warning, Critical, or Inaccessible' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Action recommendation'; Example = 'Monitor size growth'; Notes = '' }
  )

  # Duplicate Objects for ADMT
  $schemas['DuplicateObjects_ADMT'] = @(
    [pscustomobject]@{ Column = 'ConflictType'; Type = 'string'; Description = 'Type of conflict'; Example = 'SamAccountName'; Notes = 'SamAccountName, UserPrincipalName, or Mail' }
    [pscustomobject]@{ Column = 'ConflictValue'; Type = 'string'; Description = 'Conflicting value'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClasses'; Type = 'string'; Description = 'Object types involved'; Example = 'user; computer'; Notes = 'Semicolon-separated' }
    [pscustomobject]@{ Column = 'ConflictCount'; Type = 'int'; Description = 'Number of conflicts'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'ConflictingDomains'; Type = 'string'; Description = 'Domains with conflicts'; Example = 'contoso.com; fabrikam.com'; Notes = 'Semicolon-separated' }
    [pscustomobject]@{ Column = 'ConflictingDNs'; Type = 'string'; Description = 'All conflicting DNs'; Example = 'CN=jdoe,OU=Users,DC=contoso,DC=com | CN=jdoe,...'; Notes = 'Pipe-separated' }
    [pscustomobject]@{ Column = 'Severity'; Type = 'string'; Description = 'Impact severity'; Example = 'High'; Notes = 'High or Medium' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Remediation action'; Example = 'Rename before ADMT migration'; Notes = '' }
  )

  # Group Token Bloat
  $schemas['GroupToken_Bloat'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'UserPrincipalName'; Type = 'string'; Description = 'UPN'; Example = 'jdoe@contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Distinguished name'; Example = 'CN=jdoe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'EstimatedSidCount'; Type = 'int'; Description = 'Estimated SIDs in token'; Example = '950'; Notes = 'Conservative estimate (direct groups + SID history)' }
    [pscustomobject]@{ Column = 'DirectGroupCount'; Type = 'int'; Description = 'Direct group memberships'; Example = '120'; Notes = '' }
    [pscustomobject]@{ Column = 'SidHistoryCount'; Type = 'int'; Description = 'SID history entries'; Example = '5'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Token size status'; Example = 'Warning'; Notes = 'Warning or Critical' }
    [pscustomobject]@{ Column = 'Severity'; Type = 'string'; Description = 'Impact severity'; Example = 'Medium'; Notes = 'Low, Medium, or High' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Remediation action'; Example = 'Review group memberships for optimization'; Notes = '' }
  )

  # Trust Relationship Map
  $schemas['Trust_RelationshipMap'] = @(
    [pscustomobject]@{ Column = 'SourceDomain'; Type = 'string'; Description = 'Trusting domain'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'TargetDomain'; Type = 'string'; Description = 'Trusted domain'; Example = 'fabrikam.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Direction'; Type = 'string'; Description = 'Trust direction'; Example = 'Bidirectional'; Notes = 'Disabled, Inbound, Outbound, or Bidirectional' }
    [pscustomobject]@{ Column = 'TrustType'; Type = 'string'; Description = 'Type of trust'; Example = 'Uplevel (AD)'; Notes = 'Downlevel (NT4), Uplevel (AD), MIT Kerberos, or DCE' }
    [pscustomobject]@{ Column = 'IsTransitive'; Type = 'bool'; Description = 'Trust transitivity'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'SIDFilteringEnabled'; Type = 'bool'; Description = 'SID filtering status'; Example = 'True'; Notes = 'Security feature' }
    [pscustomobject]@{ Column = 'SelectiveAuth'; Type = 'bool'; Description = 'Selective authentication'; Example = 'False'; Notes = 'Restricts access' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Trust creation timestamp'; Example = '1/1/2020 12:00:00 AM'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Last modified timestamp'; Example = '1/15/2026 3:45:00 PM'; Notes = '' }
    [pscustomobject]@{ Column = 'SecurityNotes'; Type = 'string'; Description = 'Security observations'; Example = 'SID filtering enabled; Selective authentication'; Notes = 'Semicolon-separated' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Action recommendation'; Example = 'Upgrade or remove legacy trust'; Notes = '' }
  )

  # GPO Performance Analysis
  $schemas['Gpo_PerformanceAnalysis'] = @(
    [pscustomobject]@{ Column = 'GpoName'; Type = 'string'; Description = 'GPO display name'; Example = 'Default Domain Policy'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GpoId'; Type = 'string'; Description = 'GPO GUID'; Example = '{31B2F340-016D-11D2-945F-00C04FB984F9}'; Notes = '' }
    [pscustomobject]@{ Column = 'UserVersion'; Type = 'int'; Description = 'User policy version'; Example = '150'; Notes = '' }
    [pscustomobject]@{ Column = 'ComputerVersion'; Type = 'int'; Description = 'Computer policy version'; Example = '200'; Notes = '' }
    [pscustomobject]@{ Column = 'TotalVersions'; Type = 'int'; Description = 'Total version changes'; Example = '350'; Notes = 'User + Computer versions' }
    [pscustomobject]@{ Column = 'LinkCount'; Type = 'int'; Description = 'Number of GPO links'; Example = '8'; Notes = '' }
    [pscustomobject]@{ Column = 'HasWmiFilter'; Type = 'bool'; Description = 'WMI filter applied'; Example = 'True'; Notes = 'Can slow processing' }
    [pscustomobject]@{ Column = 'ComplexityScore'; Type = 'int'; Description = 'Complexity score'; Example = '7'; Notes = 'Higher = more complex' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Complexity status'; Example = 'High Complexity'; Notes = 'OK, Medium Complexity, or High Complexity' }
    [pscustomobject]@{ Column = 'Severity'; Type = 'string'; Description = 'Impact severity'; Example = 'High'; Notes = 'Low, Medium, or High' }
    [pscustomobject]@{ Column = 'PerformanceNotes'; Type = 'string'; Description = 'Performance observations'; Example = 'High version count (350); WMI filter applied'; Notes = 'Semicolon-separated' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Optimization recommendation'; Example = 'Review for consolidation or simplification'; Notes = '' }
  )

  return $schemas
}

