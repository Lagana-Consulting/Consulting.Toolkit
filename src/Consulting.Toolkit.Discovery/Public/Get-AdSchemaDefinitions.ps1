function Get-AdSchemaDefinitions {
  <#
  .SYNOPSIS
  Returns standardized schema definitions for all assessment CSV outputs.

  .DESCRIPTION
  Provides a hashtable of schema definitions used across the toolkit.
  Each schema defines column names, types, descriptions, examples, and notes
  for consistent CSV formatting.

  Used by:
  - Export-AdCsvSafe for column ordering and validation
  - Write-AdSchemaCsv for generating schema documentation
  - Reporting functions for consistent output structure

  Schema names correspond to assessment output types:
  - Forest_Summary, Domain_Summary
  - Users, Groups, Computers, OrganizationalUnits
  - PrivilegedAccounts, Migration_RiskFlags
  - GpoInventory, DnsZone_Inventory, etc.

  .EXAMPLE
  $schemas = Get-AdSchemaDefinitions
  $userSchema = $schemas['Users']
  $userSchema | Format-Table Column, Type, Description

  Views the Users schema definition.

  .EXAMPLE
  $schemas = Get-AdSchemaDefinitions
  $schemas.Keys | Sort-Object

  Lists all available schema names.

  .EXAMPLE
  $schemas = Get-AdSchemaDefinitions
  $forestCols = $schemas['Forest_Summary'] | Select-Object -ExpandProperty Column

  Gets column names for Forest_Summary schema.

  .OUTPUTS
  Hashtable. Keys are schema names (strings), values are arrays of schema
  definition objects with properties:
  - Column (string): Column name
  - Type (string): Data type (string/int/bool/datetime)
  - Description (string): Purpose of the column
  - Example (string): Sample value
  - Notes (string): Additional context

  .NOTES
  Central schema registry for the toolkit.
  Adding new assessment functions should include corresponding schema here.
  Schema definitions enforce consistency across discovery runs and reports.

  .LINK
  Export-AdCsvSafe
  Write-AdSchemaCsv
  #>
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
    [pscustomobject]@{ Column = 'ServerUsed'; Type = 'string'; Description = 'Query endpoint used'; Example = ''; Notes = '' }
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

  # User status: disabled users
  $schemas['UserStatus_DisabledUsers'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'User SAM account name'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'User display name'; Example = 'Jane Doe'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'User distinguished name'; Example = 'CN=Jane Doe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Account enabled state'; Example = 'False'; Notes = '' }
    [pscustomobject]@{ Column = 'UserPrincipalName'; Type = 'string'; Description = 'UPN'; Example = 'jdoe@contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Mail'; Type = 'string'; Description = 'Mail attribute'; Example = 'jdoe@contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Object creation time'; Example = '2022-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Object last changed time'; Example = '2026-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'LastLogonTimestampUtc'; Type = 'datetime'; Description = 'Last logon timestamp UTC'; Example = '2025-01-01T00:00:00Z'; Notes = 'Blank when unavailable' }
    [pscustomobject]@{ Column = 'LastLogonDays'; Type = 'int'; Description = 'Days since last logon'; Example = '45'; Notes = 'Blank when unavailable' }
    [pscustomobject]@{ Column = 'InactiveThresholdDays'; Type = 'int'; Description = 'Inactive threshold used by related user status exports'; Example = '180'; Notes = '' }
    [pscustomobject]@{ Column = 'PasswordLastSetUtc'; Type = 'datetime'; Description = 'Password last set UTC'; Example = '2025-01-01T00:00:00Z'; Notes = '' }
    [pscustomobject]@{ Column = 'PasswordAgeDays'; Type = 'int'; Description = 'Password age in days'; Example = '90'; Notes = '' }
    [pscustomobject]@{ Column = 'AdminCount'; Type = 'int'; Description = 'adminCount value'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'SidHistoryCount'; Type = 'int'; Description = 'SIDHistory value count'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'SPNCount'; Type = 'int'; Description = 'SPN count'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'IsKnownUpnSuffix'; Type = 'bool'; Description = 'UPN suffix is known'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'IsNonRoutableUpnSuffix'; Type = 'bool'; Description = 'UPN suffix is non-routable'; Example = 'False'; Notes = '' }
    [pscustomobject]@{ Column = 'MsDsSupportedEncryptionTypes'; Type = 'int'; Description = 'Kerberos encryption bitmask'; Example = '28'; Notes = '' }
    [pscustomobject]@{ Column = 'EncryptionTypes'; Type = 'string'; Description = 'Kerberos encryption types'; Example = 'AES128;AES256'; Notes = '' }
    [pscustomobject]@{ Column = 'EncryptionRisk'; Type = 'string'; Description = 'Encryption risk'; Example = 'Low'; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description field'; Example = 'Department user'; Notes = '' }
  )

  # User status: inactive users
  $schemas['UserStatus_InactiveUsers'] = $schemas['UserStatus_DisabledUsers']

  # Computer status: inactive workstations
  $schemas['ComputerStatus_InactiveWorkstations'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Computer name'; Example = 'PC-001'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'Computer SAM account name'; Example = 'PC-001$'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Computer distinguished name'; Example = 'CN=PC-001,CN=Computers,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Computer account enabled state'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'DnsHostName'; Type = 'string'; Description = 'DNS host name'; Example = 'pc-001.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'OperatingSystem'; Type = 'string'; Description = 'Operating system'; Example = 'Windows 10 Enterprise'; Notes = '' }
    [pscustomobject]@{ Column = 'OperatingSystemVersion'; Type = 'string'; Description = 'Operating system version'; Example = '10.0 (19045)'; Notes = '' }
    [pscustomobject]@{ Column = 'IsServer'; Type = 'bool'; Description = 'Server classification'; Example = 'False'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Object creation time'; Example = '2022-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Object last changed time'; Example = '2026-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'LastLogonTimestampUtc'; Type = 'datetime'; Description = 'Last logon timestamp UTC'; Example = '2025-01-01T00:00:00Z'; Notes = 'Blank when unavailable' }
    [pscustomobject]@{ Column = 'LastLogonDays'; Type = 'int'; Description = 'Days since last logon'; Example = '120'; Notes = '' }
    [pscustomobject]@{ Column = 'InactiveThresholdDays'; Type = 'int'; Description = 'Inactive threshold used by collector'; Example = '90'; Notes = '' }
    [pscustomobject]@{ Column = 'SPNCount'; Type = 'int'; Description = 'SPN count'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'MsDsSupportedEncryptionTypes'; Type = 'int'; Description = 'Kerberos encryption bitmask'; Example = '28'; Notes = '' }
    [pscustomobject]@{ Column = 'EncryptionTypes'; Type = 'string'; Description = 'Kerberos encryption types'; Example = 'AES128;AES256'; Notes = '' }
    [pscustomobject]@{ Column = 'EncryptionRisk'; Type = 'string'; Description = 'Encryption risk'; Example = 'Low'; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description field'; Example = 'Finance workstation'; Notes = '' }
  )

  # Computer status: inactive servers
  $schemas['ComputerStatus_InactiveServers'] = $schemas['ComputerStatus_InactiveWorkstations']

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

  # Group membership detail: empty groups
  $schemas['GroupMembership_EmptyGroups'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupName'; Type = 'string'; Description = 'Group display name'; Example = 'Legacy App Users'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupSamAccountName'; Type = 'string'; Description = 'Group SAM account name'; Example = 'LegacyAppUsers'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupDistinguishedName'; Type = 'string'; Description = 'Group distinguished name'; Example = 'CN=Legacy App Users,OU=Groups,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupCategory'; Type = 'string'; Description = 'Group category'; Example = 'Security'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupScope'; Type = 'string'; Description = 'Group scope'; Example = 'Global'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberCount'; Type = 'int'; Description = 'Direct member count'; Example = '0'; Notes = 'Direct members only' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Group creation time'; Example = '2020-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Group last changed time'; Example = '2026-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Group description'; Example = 'Legacy application access'; Notes = '' }
  )

  # Group membership detail: single-member groups
  $schemas['GroupMembership_SingleMemberGroups'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupName'; Type = 'string'; Description = 'Group display name'; Example = 'Legacy App Owners'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupSamAccountName'; Type = 'string'; Description = 'Group SAM account name'; Example = 'LegacyAppOwners'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupDistinguishedName'; Type = 'string'; Description = 'Group distinguished name'; Example = 'CN=Legacy App Owners,OU=Groups,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupCategory'; Type = 'string'; Description = 'Group category'; Example = 'Security'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupScope'; Type = 'string'; Description = 'Group scope'; Example = 'Global'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberCount'; Type = 'int'; Description = 'Direct member count'; Example = '1'; Notes = 'Direct members only' }
    [pscustomobject]@{ Column = 'MemberName'; Type = 'string'; Description = 'Only member display name'; Example = 'Jane Doe'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberSamAccountName'; Type = 'string'; Description = 'Only member SAM account name'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberObjectClass'; Type = 'string'; Description = 'Only member object class'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberDistinguishedName'; Type = 'string'; Description = 'Only member distinguished name'; Example = 'CN=Jane Doe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberEnabled'; Type = 'string'; Description = 'Only member enabled state when available'; Example = 'True'; Notes = 'Blank for objects without Enabled' }
    [pscustomobject]@{ Column = 'LastLogonTimestampUtc'; Type = 'datetime'; Description = 'Only member last logon timestamp UTC'; Example = '2025-01-01T00:00:00.0000000Z'; Notes = 'Blank when unavailable' }
    [pscustomobject]@{ Column = 'LastLogonDays'; Type = 'int'; Description = 'Days since only member last logon'; Example = '45'; Notes = 'Blank when unavailable' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Group creation time'; Example = '2020-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Group last changed time'; Example = '2026-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Group description'; Example = 'Legacy application owners'; Notes = '' }
  )

  # Group membership detail: disabled or inactive direct members
  $schemas['GroupMembership_DisabledOrInactiveMembers'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupName'; Type = 'string'; Description = 'Group display name'; Example = 'Finance Users'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupSamAccountName'; Type = 'string'; Description = 'Group SAM account name'; Example = 'FinanceUsers'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupDistinguishedName'; Type = 'string'; Description = 'Group distinguished name'; Example = 'CN=Finance Users,OU=Groups,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupCategory'; Type = 'string'; Description = 'Group category'; Example = 'Security'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupScope'; Type = 'string'; Description = 'Group scope'; Example = 'Global'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupMemberCount'; Type = 'int'; Description = 'Direct member count for the group'; Example = '12'; Notes = 'Direct members only' }
    [pscustomobject]@{ Column = 'MemberName'; Type = 'string'; Description = 'Member display name'; Example = 'Jane Doe'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberSamAccountName'; Type = 'string'; Description = 'Member SAM account name'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberObjectClass'; Type = 'string'; Description = 'Member object class'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberDistinguishedName'; Type = 'string'; Description = 'Member distinguished name'; Example = 'CN=Jane Doe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberEnabled'; Type = 'string'; Description = 'Member enabled state when available'; Example = 'False'; Notes = 'Blank for objects without Enabled' }
    [pscustomobject]@{ Column = 'LastLogonTimestampUtc'; Type = 'datetime'; Description = 'Member last logon timestamp UTC'; Example = '2024-01-01T00:00:00.0000000Z'; Notes = 'Blank when unavailable' }
    [pscustomobject]@{ Column = 'LastLogonDays'; Type = 'int'; Description = 'Days since member last logon'; Example = '365'; Notes = 'Blank when unavailable' }
    [pscustomobject]@{ Column = 'InactiveThresholdDays'; Type = 'int'; Description = 'Inactivity threshold used by the collector'; Example = '180'; Notes = '' }
    [pscustomobject]@{ Column = 'IsDisabled'; Type = 'bool'; Description = 'Member is disabled'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'IsInactive'; Type = 'bool'; Description = 'Member is inactive beyond threshold'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'FindingReason'; Type = 'string'; Description = 'Reason member was exported'; Example = 'Disabled;Inactive'; Notes = '' }
    [pscustomobject]@{ Column = 'LookupError'; Type = 'string'; Description = 'Lookup error, if member detail lookup failed'; Example = ''; Notes = '' }
  )

  # SPNs
  $schemas['SPNs'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = 'sqlsvc'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'Object class'; Example = 'user'; Notes = 'user or computer' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD distinguished name'; Example = 'CN=sqlsvc,OU=ServiceAccounts,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'ServicePrincipalName'; Type = 'string'; Description = 'Service principal name'; Example = 'MSSQLSvc/sql.contoso.com:1433'; Notes = 'Kerberos service identifier' }
    [pscustomobject]@{ Column = 'ObjectType'; Type = 'string'; Description = 'Legacy object-type alias'; Example = ''; Notes = 'Compatibility alias for ObjectClass, using User/Computer labels' }
    [pscustomobject]@{ Column = 'SPN'; Type = 'string'; Description = 'Legacy SPN alias'; Example = ''; Notes = 'Compatibility alias for ServicePrincipalName' }
  )

  # Privileged Accounts
  $schemas['PrivilegedAccounts'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Account DN'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'InPrivGroups'; Type = 'bool'; Description = 'Member of a privileged group'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'PrivGroups'; Type = 'string'; Description = 'Privileged groups'; Example = ''; Notes = 'Semicolon-delimited' }
    [pscustomobject]@{ Column = 'AdminCount'; Type = 'bool'; Description = 'adminCount-derived flag'; Example = ''; Notes = '' }
  )

  # Assessment Summary
  $schemas['Assessment_Summary'] = @(
    [pscustomobject]@{ Column = 'RunTimestamp'; Type = 'datetime'; Description = 'UTC timestamp of assessment run'; Example = '2026-01-12T13:01:56.0000000Z'; Notes = 'ISO 8601' }
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
    [pscustomobject]@{ Column = 'ObjectsRC4OnlyCount'; Type = 'int'; Description = 'Objects advertising RC4 without AES'; Example = '0'; Notes = 'Based on explicit encryption capabilities; unset values are not classified as RC4-only' }
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
    [pscustomobject]@{ Column = 'DN'; Type = 'string'; Description = 'AD DN for DHCP object'; Example = 'CN=dhcp01.contoso.com,...'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Authorization status'; Example = 'Authorized'; Notes = '' }
    [pscustomobject]@{ Column = 'Notes'; Type = 'string'; Description = 'Notes'; Example = 'AD-authorized DHCP server'; Notes = '' }
  )

  # Sysvol Size Analysis
  $schemas['Sysvol_SizeAnalysis'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SysvolPath'; Type = 'string'; Description = 'UNC path to SYSVOL'; Example = '\\contoso.com\\SYSVOL\\contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SizeGB'; Type = 'decimal'; Description = 'SYSVOL size in GB'; Example = '2.3'; Notes = '' }
    [pscustomobject]@{ Column = 'GpoFolderCount'; Type = 'int'; Description = 'Count of GPO folders'; Example = '24'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Status indicator'; Example = 'Warning'; Notes = '' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Remediation recommendation'; Example = 'Monitor size growth'; Notes = '' }
  )

  # Site Link Cost Analysis
  $schemas['SiteLink_CostAnalysis'] = @(
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Site link name'; Example = 'DEFAULTIPSITELINK'; Notes = '' }
    [pscustomobject]@{ Column = 'Cost'; Type = 'int'; Description = 'Replication cost'; Example = '100'; Notes = '' }
    [pscustomobject]@{ Column = 'ReplicationInterval'; Type = 'int'; Description = 'Replication frequency (minutes)'; Example = '15'; Notes = '' }
    [pscustomobject]@{ Column = 'SitesIncluded'; Type = 'string'; Description = 'Sites in link'; Example = 'HQ;Branch1'; Notes = '' }
    [pscustomobject]@{ Column = 'Assessment'; Type = 'string'; Description = 'Cost assessment'; Example = 'Normal'; Notes = '' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Recommendation'; Example = 'No action needed'; Notes = '' }
  )

  # FSMO Role Availability
  $schemas['FsmoRole_Availability'] = @(
    [pscustomobject]@{ Column = 'Scope'; Type = 'string'; Description = 'Scope (Forest or Domain)'; Example = 'Forest'; Notes = '' }
    [pscustomobject]@{ Column = 'Role'; Type = 'string'; Description = 'FSMO role name'; Example = 'SchemaMaster'; Notes = '' }
    [pscustomobject]@{ Column = 'Holder'; Type = 'string'; Description = 'FSMO role holder'; Example = 'dc1.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'IsAvailable'; Type = 'bool'; Description = 'Ping available'; Example = 'True'; Notes = '' }
  )

  # Trust Relationship Map
  $schemas['Trust_RelationshipMap'] = @(
    [pscustomobject]@{ Column = 'SourceDomain'; Type = 'string'; Description = 'Source domain'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'TargetDomain'; Type = 'string'; Description = 'Target domain'; Example = 'fabrikam.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Direction'; Type = 'string'; Description = 'Trust direction'; Example = 'Bidirectional'; Notes = '' }
    [pscustomobject]@{ Column = 'TrustType'; Type = 'string'; Description = 'Trust type'; Example = 'Uplevel (AD)'; Notes = '' }
    [pscustomobject]@{ Column = 'IsTransitive'; Type = 'bool'; Description = 'Transitivity flag'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'SIDFilteringEnabled'; Type = 'bool'; Description = 'SID filtering'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'SelectiveAuth'; Type = 'bool'; Description = 'Selective authentication'; Example = 'False'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Trust creation time'; Example = '2024-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Trust modified time'; Example = '2025-06-01'; Notes = '' }
    [pscustomobject]@{ Column = 'SecurityNotes'; Type = 'string'; Description = 'Security notes'; Example = 'SID filtering enabled'; Notes = '' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Recommendation'; Example = 'No immediate action'; Notes = '' }
  )

  # Group Nesting Depth
  $schemas['GroupNestingDepth'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Group name'; Example = 'IT_Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = 'IT_Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'AD DN'; Example = 'CN=IT_Admins,OU=Groups,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'NestingDepth'; Type = 'int'; Description = 'Depth of nesting'; Example = '3'; Notes = '' }
    [pscustomobject]@{ Column = 'DepthWarning'; Type = 'string'; Description = 'Warning flag'; Example = 'High'; Notes = '' }
  )

  # Cross-domain Group Membership
  $schemas['CrossDomainGroupMembership'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupName'; Type = 'string'; Description = 'Group name'; Example = 'IT_Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupDn'; Type = 'string'; Description = 'Group DN'; Example = 'CN=IT_Admins,OU=Groups,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'CrossDomainMemberCount'; Type = 'int'; Description = 'Cross-domain member count'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'CrossDomainMembers'; Type = 'string'; Description = 'Member DN + domain'; Example = 'CN=User1,DC=fabrikam,DC=com|fabrikam.com'; Notes = '' }
  )

  # Weak Password Policies
  $schemas['WeakPasswordPolicies'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'PolicyType'; Type = 'string'; Description = 'DefaultDomain or FGPP'; Example = 'DefaultDomain'; Notes = '' }
    [pscustomobject]@{ Column = 'PolicyName'; Type = 'string'; Description = 'Policy name'; Example = 'Default Domain Policy'; Notes = '' }
    [pscustomobject]@{ Column = 'Weaknesses'; Type = 'string'; Description = 'Weakness list'; Example = 'MinLength=10;MaxAge=180'; Notes = '' }
    [pscustomobject]@{ Column = 'WeaknessCount'; Type = 'int'; Description = 'Weakness count'; Example = '3'; Notes = '' }
    [pscustomobject]@{ Column = 'RiskLevel'; Type = 'string'; Description = 'Risk level'; Example = 'High'; Notes = '' }
  )

  # Empty Groups
  $schemas['EmptyGroups'] = @($schemas['GroupMembership_EmptyGroups'])

  # Duplicate SPNs
  $schemas['DuplicateSPNs'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ServicePrincipalName'; Type = 'string'; Description = 'SPN'; Example = 'MSSQLSvc/sql.contoso.com:1433'; Notes = '' }
    [pscustomobject]@{ Column = 'ConflictCount'; Type = 'int'; Description = 'Number of conflicting objects'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'ConflictingObjects'; Type = 'string'; Description = 'SAM names'; Example = 'svcSQL;svcSQL2'; Notes = '' }
    [pscustomobject]@{ Column = 'ConflictingDNs'; Type = 'string'; Description = 'Object DNs'; Example = 'CN=svcSQL,...;CN=svcSQL2,...'; Notes = '' }
    [pscustomobject]@{ Column = 'RiskLevel'; Type = 'string'; Description = 'Risk level'; Example = 'High'; Notes = '' }
  )

  # Top SPNs by Type
  $schemas['TopSPNsByType'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ServiceType'; Type = 'string'; Description = 'Service type'; Example = 'MSSQLSvc'; Notes = '' }
    [pscustomobject]@{ Column = 'Count'; Type = 'int'; Description = 'Count of SPNs'; Example = '15'; Notes = '' }
    [pscustomobject]@{ Column = 'ExampleSPN'; Type = 'string'; Description = 'Example SPN'; Example = 'MSSQLSvc/sql.contoso.com:1433'; Notes = '' }
  )

  # OU Depth Analysis
  $schemas['OuDepthAnalysis'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'OU name'; Example = 'Workstations'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'OU DN'; Example = 'OU=Workstations,OU=Devices,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'Depth'; Type = 'int'; Description = 'Depth of OU'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'DepthWarning'; Type = 'string'; Description = 'Warning flag'; Example = 'Normal'; Notes = '' }
    [pscustomobject]@{ Column = 'IsTopLevel'; Type = 'bool'; Description = 'Top-level OU'; Example = 'False'; Notes = '' }
  )

  # Disabled Accounts
  $schemas['DisabledAccounts'] = @(
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'user or computer'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM name'; Example = 'olduser'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Name'; Example = 'Old User'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'DN'; Example = 'CN=Old User,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Created'; Example = '2020-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Changed'; Example = '2024-12-01'; Notes = '' }
    [pscustomobject]@{ Column = 'DaysSinceChange'; Type = 'int'; Description = 'Whole elapsed days since last change'; Example = '120'; Notes = 'Blank when the change date is unknown; future dates yield zero' }
    [pscustomobject]@{ Column = 'CleanupCandidate'; Type = 'string'; Description = 'Cleanup candidate'; Example = 'Yes'; Notes = 'Yes/No; Unknown when the change date is missing' }
  )

  # AdminSDHolder Impact
  $schemas['AdminSdHolderImpact'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'Object class'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Object name'; Example = 'Domain Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'DN'; Example = 'CN=Domain Admins,CN=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Created'; Example = '2020-01-01'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Changed'; Example = '2024-12-01'; Notes = '' }
    [pscustomobject]@{ Column = 'AdminCount'; Type = 'int'; Description = 'adminCount'; Example = '1'; Notes = '' }
    [pscustomobject]@{ Column = 'Impact'; Type = 'string'; Description = 'Impact description'; Example = 'ACL inheritance disabled'; Notes = '' }
  )

  # Tombstone Lifetime
  $schemas['TombstoneLifetime'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'TombstoneLifetime'; Type = 'int'; Description = 'Tombstone lifetime (days)'; Example = '180'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Status'; Example = 'Acceptable'; Notes = '' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Recommendation'; Example = 'No action needed'; Notes = '' }
  )

  # Group Token Bloat
  $schemas['GroupToken_Bloat'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS root'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM name'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'UserPrincipalName'; Type = 'string'; Description = 'UPN'; Example = 'jdoe@contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'DN'; Example = 'CN=jdoe,OU=Users,DC=contoso,DC=com'; Notes = '' }
    [pscustomobject]@{ Column = 'EstimatedSidCount'; Type = 'int'; Description = 'Estimated SID count'; Example = '900'; Notes = '' }
    [pscustomobject]@{ Column = 'DirectGroupCount'; Type = 'int'; Description = 'Direct groups'; Example = '55'; Notes = '' }
    [pscustomobject]@{ Column = 'SidHistoryCount'; Type = 'int'; Description = 'SID history count'; Example = '4'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Status'; Example = 'Warning'; Notes = '' }
    [pscustomobject]@{ Column = 'Severity'; Type = 'string'; Description = 'Severity'; Example = 'Medium'; Notes = '' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Recommendation'; Example = 'Review group memberships'; Notes = '' }
  )

  # GPO Performance Analysis
  $schemas['Gpo_PerformanceAnalysis'] = @(
    [pscustomobject]@{ Column = 'GpoName'; Type = 'string'; Description = 'GPO name'; Example = 'Default Domain Policy'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GpoId'; Type = 'string'; Description = 'GPO ID'; Example = '{GUID}'; Notes = '' }
    [pscustomobject]@{ Column = 'UserVersion'; Type = 'int'; Description = 'User version'; Example = '32'; Notes = '' }
    [pscustomobject]@{ Column = 'ComputerVersion'; Type = 'int'; Description = 'Computer version'; Example = '18'; Notes = '' }
    [pscustomobject]@{ Column = 'TotalVersions'; Type = 'int'; Description = 'Total version count'; Example = '50'; Notes = '' }
    [pscustomobject]@{ Column = 'LinkCount'; Type = 'int'; Description = 'Link count'; Example = '8'; Notes = '' }
    [pscustomobject]@{ Column = 'HasWmiFilter'; Type = 'bool'; Description = 'WMI filter'; Example = 'True'; Notes = '' }
    [pscustomobject]@{ Column = 'ComplexityScore'; Type = 'int'; Description = 'Complexity score'; Example = '4'; Notes = '' }
    [pscustomobject]@{ Column = 'Status'; Type = 'string'; Description = 'Status'; Example = 'Medium Complexity'; Notes = '' }
    [pscustomobject]@{ Column = 'Severity'; Type = 'string'; Description = 'Severity'; Example = 'Medium'; Notes = '' }
    [pscustomobject]@{ Column = 'PerformanceNotes'; Type = 'string'; Description = 'Notes'; Example = 'High version count'; Notes = '' }
    [pscustomobject]@{ Column = 'Recommendation'; Type = 'string'; Description = 'Recommendation'; Example = 'Monitor GPO application time'; Notes = '' }
  )

  # =========================
  # Security (ADCS / Tier0 / Delegation / SPN / DC Signals)
  # =========================

  # Forest: ADCS Enterprise CAs
  $schemas['Forest_Security_ADCS_EnterpriseCAs'] = @(
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'Forest DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'CAName'; Type = 'string'; Description = 'Enterprise CA common name'; Example = 'CONTOSO-CA01'; Notes = '' }
    [pscustomobject]@{ Column = 'DnsHostName'; Type = 'string'; Description = 'CA host FQDN'; Example = 'ca01.contoso.com'; Notes = 'If available' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'CA object DN'; Example = 'CN=CONTOSO-CA01,...'; Notes = '' }
    [pscustomobject]@{ Column = 'CertificateSubject'; Type = 'string'; Description = 'CA cert subject'; Example = 'CN=CONTOSO-CA01'; Notes = '' }
    [pscustomobject]@{ Column = 'CertificateSerialNumber'; Type = 'string'; Description = 'CA cert serial number'; Example = '01A2...'; Notes = '' }
    [pscustomobject]@{ Column = 'ValidityNotAfterUtc'; Type = 'datetime'; Description = 'CA cert expiration (UTC)'; Example = '2027-05-01T00:00:00Z'; Notes = '' }
    [pscustomobject]@{ Column = 'PublishedTemplates'; Type = 'string'; Description = 'Templates published by this CA'; Example = 'User;Machine'; Notes = 'Semicolon-delimited' }
  )

  # Forest: ADCS Enrollment Services -> Templates mapping
  $schemas['Forest_Security_ADCS_EnrollmentServicesTemplates'] = @(
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'Forest DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'EnrollmentServiceName'; Type = 'string'; Description = 'Enrollment Services name'; Example = 'CONTOSO-CA01'; Notes = '' }
    [pscustomobject]@{ Column = 'EnrollmentServiceDn'; Type = 'string'; Description = 'Enrollment Services DN'; Example = 'CN=...,CN=Enrollment Services,...'; Notes = '' }
    [pscustomobject]@{ Column = 'TemplateName'; Type = 'string'; Description = 'Certificate template name'; Example = 'User'; Notes = '' }
    [pscustomobject]@{ Column = 'TemplateOid'; Type = 'string'; Description = 'Template OID'; Example = '1.3.6.1.4.1...'; Notes = 'If available' }
  )

  # Forest: ADCS Certificate Templates
  $schemas['Forest_Security_ADCS_CertificateTemplates'] = @(
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'Forest DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'TemplateName'; Type = 'string'; Description = 'Template display/name'; Example = 'User'; Notes = '' }
    [pscustomobject]@{ Column = 'TemplateCn'; Type = 'string'; Description = 'Template CN'; Example = 'User'; Notes = '' }
    [pscustomobject]@{ Column = 'TemplateOid'; Type = 'string'; Description = 'Template OID'; Example = '1.3.6.1.4.1...'; Notes = '' }
    [pscustomobject]@{ Column = 'SchemaVersion'; Type = 'int'; Description = 'Template schema version'; Example = '2'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Template appears enabled/usable'; Example = 'true'; Notes = 'Best-effort depending on collection' }
    [pscustomobject]@{ Column = 'EnrolleeSuppliesSubject'; Type = 'bool'; Description = 'Enrollee supplies subject'; Example = 'false'; Notes = 'Important for abuse paths' }
    [pscustomobject]@{ Column = 'ClientAuth'; Type = 'bool'; Description = 'EKU includes client auth'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'SmartcardLogon'; Type = 'bool'; Description = 'EKU includes smartcard logon'; Example = 'false'; Notes = '' }
    [pscustomobject]@{ Column = 'AnyPurpose'; Type = 'bool'; Description = 'EKU any purpose'; Example = 'false'; Notes = '' }
    [pscustomobject]@{ Column = 'RequiresManagerApproval'; Type = 'bool'; Description = 'Manager approval required'; Example = 'false'; Notes = '' }
    [pscustomobject]@{ Column = 'AuthorizedSignatures'; Type = 'int'; Description = 'Authorized signatures required'; Example = '0'; Notes = '' }
    [pscustomobject]@{ Column = 'SANRequirements'; Type = 'string'; Description = 'Subject/SAN requirement mode'; Example = 'EnrolleeSuppliesSubject'; Notes = 'ESC-path relevant signal' }
    [pscustomobject]@{ Column = 'AuthenticationRequirements'; Type = 'string'; Description = 'Additional auth/approval requirements'; Example = 'ManagerApproval;AuthorizedSignatures=1'; Notes = 'Best-effort summary' }
  )

  # Forest: Trust hardening signals
  $schemas['Forest_Security_Trusts'] = @(
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Trust object name'; Example = 'fabrikam.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Source'; Type = 'string'; Description = 'Source domain/forest'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Target'; Type = 'string'; Description = 'Target domain/forest'; Example = 'fabrikam.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Direction'; Type = 'string'; Description = 'Trust direction'; Example = 'Bidirectional'; Notes = '' }
    [pscustomobject]@{ Column = 'TrustType'; Type = 'string'; Description = 'Trust type'; Example = 'External'; Notes = '' }
    [pscustomobject]@{ Column = 'TrustAttributes'; Type = 'string'; Description = 'Raw trust attributes'; Example = 'FOREST_TRANSITIVE'; Notes = '' }
    [pscustomobject]@{ Column = 'ForestTransitive'; Type = 'bool'; Description = 'Forest transitive'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'SelectiveAuthentication'; Type = 'bool'; Description = 'Selective authentication enabled'; Example = 'false'; Notes = '' }
    [pscustomobject]@{ Column = 'SIDFilteringForestAware'; Type = 'bool'; Description = 'Forest-aware SID filtering'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'SIDFilteringQuarantined'; Type = 'bool'; Description = 'Quarantine SID filtering'; Example = 'false'; Notes = '' }
    [pscustomobject]@{ Column = 'SIDFilteringStatus'; Type = 'string'; Description = 'Derived SID filtering status'; Example = 'ForestAware'; Notes = '' }
    [pscustomobject]@{ Column = 'UsesAESKeys'; Type = 'bool'; Description = 'Trust uses AES keys'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'UsesRC4Encryption'; Type = 'bool'; Description = 'Trust uses RC4'; Example = 'false'; Notes = '' }
  )

  # Forest: ADCS Template Permissions (flattened ACEs)
  $schemas['Forest_Security_ADCS_CertificateTemplatePermissions'] = @(
    [pscustomobject]@{ Column = 'ForestName'; Type = 'string'; Description = 'Forest DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'TemplateName'; Type = 'string'; Description = 'Template name'; Example = 'User'; Notes = '' }
    [pscustomobject]@{ Column = 'Principal'; Type = 'string'; Description = 'Trustee (resolved)'; Example = 'CONTOSO\Domain Users'; Notes = '' }
    [pscustomobject]@{ Column = 'PrincipalSid'; Type = 'string'; Description = 'Trustee SID'; Example = 'S-1-5-21-...'; Notes = '' }
    [pscustomobject]@{ Column = 'Right'; Type = 'string'; Description = 'Permission/right'; Example = 'Enroll'; Notes = 'Enroll/AutoEnroll/WriteDacl/WriteOwner/GenericAll/etc' }
    [pscustomobject]@{ Column = 'AccessType'; Type = 'string'; Description = 'Allow/Deny'; Example = 'Allow'; Notes = '' }
    [pscustomobject]@{ Column = 'Inherited'; Type = 'bool'; Description = 'Inherited ACE'; Example = 'false'; Notes = '' }
  )

  # Domain: Privileged Group Members (Tier0)
  $schemas['Domain_Security_PrivilegedGroupMembers'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupName'; Type = 'string'; Description = 'Privileged group name'; Example = 'Domain Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupDn'; Type = 'string'; Description = 'Group DN'; Example = 'CN=Domain Admins,CN=Users,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberSamAccountName'; Type = 'string'; Description = 'Member sAMAccountName'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberDn'; Type = 'string'; Description = 'Member DN'; Example = 'CN=John Doe,OU=Users,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberObjectClass'; Type = 'string'; Description = 'user/group/computer'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'IsDirectMember'; Type = 'bool'; Description = 'Direct membership vs nested'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'MembershipPath'; Type = 'string'; Description = 'Nested chain (if any)'; Example = 'GroupA > GroupB'; Notes = 'Semicolon-delimited or arrow-delimited' }
  )

  # Domain: adminCount=1 objects
  $schemas['Domain_Security_AdminCountObjects'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'user/group'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'sAMAccountName'; Example = 'svc_sql'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=svc_sql,OU=Svc,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'AdminCount'; Type = 'int'; Description = 'adminCount value'; Example = '1'; Notes = 'Typically 1' }
    [pscustomobject]@{ Column = 'IsProtectedByAdminSDHolder'; Type = 'bool'; Description = 'Best-effort flag'; Example = 'true'; Notes = 'If your collector infers it' }
  )

  # Domain: Protected Users group members
  $schemas['Domain_Security_ProtectedUsers'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberSamAccountName'; Type = 'string'; Description = 'Member sAMAccountName'; Example = 'jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberDn'; Type = 'string'; Description = 'Member DN'; Example = 'CN=John Doe,OU=Users,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'MemberObjectClass'; Type = 'string'; Description = 'user/group'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'GroupName'; Type = 'string'; Description = 'Protected group name'; Example = ''; Notes = '' }
  )

  # Domain: Delegation - Unconstrained
  $schemas['Domain_Security_DelegationUnconstrained'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'computer/user'; Example = 'computer'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Object name'; Example = 'APP01$'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=APP01,OU=Servers,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'TrustedForDelegation'; Type = 'bool'; Description = 'Unconstrained delegation flag'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'SPNCount'; Type = 'int'; Description = 'Number of registered SPNs'; Example = ''; Notes = '' }
  )

  # Domain: Delegation - Constrained
  $schemas['Domain_Security_DelegationConstrained'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'computer/user'; Example = 'computer'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Object name'; Example = 'WEB01$'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=WEB01,OU=Servers,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'AllowedToDelegateTo'; Type = 'string'; Description = 'SPNs in msDS-AllowedToDelegateTo'; Example = 'HTTP/app01.contoso.com'; Notes = 'Semicolon-delimited' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'TargetCount'; Type = 'int'; Description = 'Number of allowed delegation targets'; Example = ''; Notes = '' }
  )

  # Domain: Delegation - Protocol Transition (S4U2Self)
  $schemas['Domain_Security_DelegationProtocolTransition'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'computer/user'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Object name'; Example = 'svc_web'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=svc_web,OU=Svc,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'TrustedToAuthForDelegation'; Type = 'bool'; Description = 'Protocol transition enabled'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'AllowedToDelegateTo'; Type = 'string'; Description = 'SPNs in msDS-AllowedToDelegateTo'; Example = 'HTTP/app01.contoso.com'; Notes = 'Semicolon-delimited' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'SAM account name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'TargetCount'; Type = 'int'; Description = 'Number of allowed delegation targets'; Example = ''; Notes = '' }
  )

  # Domain: Resource-Based Constrained Delegation (RBCD)
  $schemas['Domain_Security_DelegationRBCD'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'TargetName'; Type = 'string'; Description = 'Target resource name'; Example = 'FILE01$'; Notes = '' }
    [pscustomobject]@{ Column = 'TargetDn'; Type = 'string'; Description = 'Target DN'; Example = 'CN=FILE01,OU=Servers,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'AllowedPrincipal'; Type = 'string'; Description = 'Principal allowed via msDS-AllowedToActOnBehalfOfOtherIdentity'; Example = 'CONTOSO\\svc_app'; Notes = '' }
    [pscustomobject]@{ Column = 'AllowedPrincipalSid'; Type = 'string'; Description = 'Principal SID'; Example = 'S-1-5-21-...'; Notes = '' }
    [pscustomobject]@{ Column = 'AccessType'; Type = 'string'; Description = 'Allow/Deny (if ACE expanded)'; Example = 'Allow'; Notes = 'If you flatten ACEs' }
  )

  # Domain: SPN Accounts (security-focused view of service principals)
  $schemas['Domain_Security_SpnAccounts'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'user/computer'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'Account name'; Example = 'svc_sql'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=svc_sql,OU=Svc,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'SPNs'; Type = 'string'; Description = 'ServicePrincipalName values'; Example = 'MSSQLSvc/sql01.contoso.com:1433'; Notes = 'Semicolon-delimited' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Account enabled'; Example = 'true'; Notes = 'If available in your collector' }
    [pscustomobject]@{ Column = 'PasswordLastSetUtc'; Type = 'datetime'; Description = 'Password last set (UTC)'; Example = '2025-12-10T01:02:03Z'; Notes = 'If you collect it' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Account name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'SPNCount'; Type = 'int'; Description = 'Number of registered SPNs'; Example = ''; Notes = '' }
  )

  # Domain: Domain Controller security signals (best-effort)
  $schemas['Domain_Security_DomainControllerSecuritySignals'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'DomainController'; Type = 'string'; Description = 'DC host name'; Example = 'dc01.contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'Signal'; Type = 'string'; Description = 'Signal name'; Example = 'LDAPSigning'; Notes = 'A single signal per row is easiest to consume' }
    [pscustomobject]@{ Column = 'Value'; Type = 'string'; Description = 'Signal value'; Example = 'Required'; Notes = 'Could be string/bool/int; keep as string' }
    [pscustomobject]@{ Column = 'Evidence'; Type = 'string'; Description = 'Optional evidence/source'; Example = 'Registry/Policy'; Notes = 'If you capture it' }
  )

  # Domain: recently created objects (users/groups/computers)
  $schemas['Domain_Security_RecentlyCreatedObjects'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectClass'; Type = 'string'; Description = 'user/group/computer/gpo'; Example = 'user'; Notes = '' }
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Object name'; Example = 'SQL Service'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'sAMAccountName'; Example = 'svc_sql'; Notes = 'Blank for some objects' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=...,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectGuid'; Type = 'string'; Description = 'Object GUID'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Creation time'; Example = '2026-02-01T12:00:00'; Notes = '' }
    [pscustomobject]@{ Column = 'LookbackDays'; Type = 'int'; Description = 'Lookback window days'; Example = '10'; Notes = '' }
  )

  # Domain: built-in Administrator signals (RID 500)
  $schemas['Domain_Security_BuiltInAdministratorSignals'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'sAMAccountName'; Example = 'Administrator'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=Administrator,CN=Users,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectGuid'; Type = 'string'; Description = 'Object GUID'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Enabled flag'; Example = 'false'; Notes = '' }
    [pscustomobject]@{ Column = 'UserAccountControl'; Type = 'int'; Description = 'UAC flags integer'; Example = '512'; Notes = '' }
    [pscustomobject]@{ Column = 'PasswordLastSet'; Type = 'datetime'; Description = 'Password last set'; Example = '2026-01-01T00:00:00'; Notes = '' }
    [pscustomobject]@{ Column = 'PwdLastSetRaw'; Type = 'string'; Description = 'Raw pwdLastSet'; Example = '133...'; Notes = '' }
    [pscustomobject]@{ Column = 'LastLogonDate'; Type = 'datetime'; Description = 'Replicated last logon date'; Example = '2026-02-10T00:00:00'; Notes = 'From lastLogonTimestamp-derived field' }
    [pscustomobject]@{ Column = 'LastLogonTimestamp'; Type = 'string'; Description = 'Raw lastLogonTimestamp'; Example = '133...'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenCreated'; Type = 'datetime'; Description = 'Creation time'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'WhenChanged'; Type = 'datetime'; Description = 'Changed time'; Example = '...'; Notes = '' }
  )

  # Domain: AS-REP roastable users
  $schemas['Domain_Security_AsrepRoastableUsers'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'sAMAccountName'; Example = 'user1'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=...,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectGuid'; Type = 'string'; Description = 'Object GUID'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Enabled flag'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'UserAccountControl'; Type = 'int'; Description = 'UAC flags integer'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'PasswordLastSet'; Type = 'datetime'; Description = 'Password last set'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'IsAsrepRoastable'; Type = 'bool'; Description = 'Always true'; Example = 'true'; Notes = '' }
  )

  # Domain: privileged accounts password age
  $schemas['Domain_Security_PrivilegedPasswordAge'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'SamAccountName'; Type = 'string'; Description = 'sAMAccountName'; Example = 'adm_jdoe'; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'Object DN'; Example = 'CN=...,DC=...'; Notes = '' }
    [pscustomobject]@{ Column = 'ObjectGuid'; Type = 'string'; Description = 'Object GUID'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'Enabled'; Type = 'bool'; Description = 'Enabled flag'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'InPrivGroups'; Type = 'bool'; Description = 'In privileged groups'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'PrivGroups'; Type = 'string'; Description = 'Privileged groups'; Example = 'Domain Admins;Administrators'; Notes = 'Semicolon-delimited' }
    [pscustomobject]@{ Column = 'AdminCount'; Type = 'bool'; Description = 'adminCount-derived flag'; Example = 'true'; Notes = '' }
    [pscustomobject]@{ Column = 'PasswordLastSet'; Type = 'datetime'; Description = 'Password last set'; Example = '...'; Notes = '' }
    [pscustomobject]@{ Column = 'PasswordAgeDays'; Type = 'int'; Description = 'Password age in days'; Example = '180'; Notes = '' }
  )

  # Domain: GPO delegation/permissions
  $schemas['Domain_GPO_Delegation'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'Domain DNS name'; Example = 'contoso.com'; Notes = '' }
    [pscustomobject]@{ Column = 'GpoDisplayName'; Type = 'string'; Description = 'GPO display name'; Example = 'Default Domain Policy'; Notes = '' }
    [pscustomobject]@{ Column = 'GpoId'; Type = 'string'; Description = 'GPO GUID'; Example = '{...}'; Notes = '' }
    [pscustomobject]@{ Column = 'Trustee'; Type = 'string'; Description = 'Trustee name'; Example = 'CONTOSO\\Domain Admins'; Notes = '' }
    [pscustomobject]@{ Column = 'TrusteeType'; Type = 'string'; Description = 'Trustee type'; Example = 'Group'; Notes = '' }
    [pscustomobject]@{ Column = 'Permission'; Type = 'string'; Description = 'Permission'; Example = 'GpoEditDeleteModifySecurity'; Notes = '' }
    [pscustomobject]@{ Column = 'Inherited'; Type = 'bool'; Description = 'Inherited'; Example = 'false'; Notes = 'May be null depending on platform' }
  )

  $schemas['GpoInventory'] = @(
    [pscustomobject]@{ Column = 'DomainFqdn'; Type = 'string'; Description = 'DomainFqdn'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'DisplayName'; Type = 'string'; Description = 'DisplayName'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Id'; Type = 'string'; Description = 'Id'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Owner'; Type = 'string'; Description = 'Owner'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'CreationTime'; Type = 'datetime'; Description = 'CreationTime'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'ModificationTime'; Type = 'datetime'; Description = 'ModificationTime'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'GpoStatus'; Type = 'string'; Description = 'GpoStatus'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'UserVersion'; Type = 'int'; Description = 'UserVersion'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'ComputerVersion'; Type = 'int'; Description = 'ComputerVersion'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'WmiFilter'; Type = 'string'; Description = 'WmiFilter'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'GpoId'; Type = 'string'; Description = 'GpoId'; Example = ''; Notes = '' }
  )

  $schemas['Forest_Sites'] = @(
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'DistinguishedName'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description'; Example = ''; Notes = '' }
  )

  $schemas['Forest_Subnets'] = @(
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Site'; Type = 'string'; Description = 'Site'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Location'; Type = 'string'; Description = 'Location'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'DistinguishedName'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description'; Example = ''; Notes = '' }
  )

  $schemas['Forest_SiteLinks'] = @(
    [pscustomobject]@{ Column = 'Name'; Type = 'string'; Description = 'Name'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Cost'; Type = 'int'; Description = 'Cost'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'ReplicationFrequencyInMinutes'; Type = 'int'; Description = 'ReplicationFrequencyInMinutes'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'SitesIncluded'; Type = 'string'; Description = 'SitesIncluded'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'DistinguishedName'; Type = 'string'; Description = 'DistinguishedName'; Example = ''; Notes = '' }
    [pscustomobject]@{ Column = 'Description'; Type = 'string'; Description = 'Description'; Example = ''; Notes = '' }
  )

  return $schemas
}
