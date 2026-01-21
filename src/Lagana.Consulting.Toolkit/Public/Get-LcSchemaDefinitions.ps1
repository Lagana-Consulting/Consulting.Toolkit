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

  return $schemas
}
