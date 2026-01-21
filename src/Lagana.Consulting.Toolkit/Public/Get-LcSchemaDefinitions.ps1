function Get-LcSchemaDefinitions {
  [CmdletBinding()]
  param()

  # Return: hashtable of SchemaName -> string[] Columns
  # Schemas reflect the current output columns from discovery functions (LC__ prefixed files)

  $schemas = @{}

  # Forest-level summaries
  $schemas['Forest_Summary'] = @(
    'ForestName',
    'RootDomain',
    'ForestMode',
    'Domains',
    'DomainCount',
    'UPNSuffixes',
    'UPNSuffixCount',
    'SchemaMaster',
    'DomainNamingMaster'
  )

  $schemas['Forest_UPNSuffixes'] = @(
    'ForestName',
    'Suffix',
    'IsKnownSuffix',
    'IsNonRoutable'
  )

  # Domain-level summaries and infrastructure
  $schemas['Domain_Summary'] = @(
    'DomainFqdn',
    'DomainDn',
    'NetBIOSName',
    'DomainMode',
    'PdcEmulator',
    'RidMaster',
    'InfrastructureMaster'
  )

  $schemas['Domain_DomainControllers'] = @(
    'DomainFqdn',
    'Name',
    'SamAccountName',
    'DistinguishedName',
    'Enabled',
    'OperatingSystem',
    'OperatingSystemVersion',
    'WhenCreated',
    'WhenChanged',
    'IsGlobalCatalog',
    'IsReadOnly',
    'IsWritable'
  )

  # Identity objects
  $schemas['Domain_Identity_Users'] = @(
    'DomainFqdn',
    'SamAccountName',
    'Name',
    'DistinguishedName',
    'Enabled',
    'UserPrincipalName',
    'Mail',
    'UPNSuffix',
    'IsKnownUpnSuffix',
    'IsNonRoutableUpnSuffix',
    'WhenCreated',
    'WhenChanged',
    'LastLogonTimestampUtc',
    'LastLogonDays',
    'PasswordLastSetUtc',
    'PasswordAgeDays',
    'AdminCount',
    'SidHistoryCount',
    'SPNCount',
    'MsDsSupportedEncryptionTypes',
    'EncryptionTypes',
    'EncryptionRisk',
    'Description'
  )

  $schemas['Domain_Identity_Computers'] = @(
    'DomainFqdn',
    'Name',
    'SamAccountName',
    'DistinguishedName',
    'Enabled',
    'DnsHostName',
    'OperatingSystem',
    'OperatingSystemVersion',
    'IsServer',
    'WhenCreated',
    'WhenChanged',
    'LastLogonTimestampUtc',
    'LastLogonDays',
    'SPNCount',
    'MsDsSupportedEncryptionTypes',
    'EncryptionTypes',
    'EncryptionRisk',
    'Description'
  )

  $schemas['Domain_Identity_Groups'] = @(
    'DomainFqdn',
    'Name',
    'SamAccountName',
    'DistinguishedName',
    'GroupCategory',
    'GroupScope',
    'Mail',
    'WhenCreated',
    'WhenChanged',
    'Description'
  )

  $schemas['Domain_Identity_Spns'] = @(
    'DomainFqdn',
    'SamAccountName',
    'ObjectClass',
    'DistinguishedName',
    'ServicePrincipalName'
  )

  # Directory structure
  $schemas['Domain_Structure_OrganizationalUnits'] = @(
    'DomainFqdn',
    'Name',
    'DistinguishedName',
    'Description',
    'WhenCreated',
    'WhenChanged',
    'Level',
    'IsTopLevel'
  )

  # GPO objects
  $schemas['Domain_GPO_Inventory'] = @(
    'DomainFqdn',
    'DisplayName',
    'Id',
    'Owner',
    'CreationTime',
    'ModificationTime',
    'GpoStatus',
    'Description',
    'UserVersion',
    'ComputerVersion',
    'WmiFilter'
  )

  $schemas['Domain_GPO_Links'] = @(
    'DomainFqdn',
    'GpoId',
    'GpoDisplayName',
    'LinkTarget',
    'LinkEnabled',
    'LinkEnforced',
    'LinkOrder'
  )

  # Security and risk assessment
  $schemas['Domain_Security_KerberosEncryption_Users'] = @(
    'DomainFqdn',
    'SamAccountName',
    'Name',
    'Enabled',
    'MsDsSupportedEncryptionTypes',
    'EncryptionTypes',
    'EncryptionRisk'
  )

  $schemas['Domain_Security_KerberosEncryption_Computers'] = @(
    'DomainFqdn',
    'Name',
    'SamAccountName',
    'Enabled',
    'MsDsSupportedEncryptionTypes',
    'EncryptionTypes',
    'EncryptionRisk'
  )

  $schemas['Domain_Security_PrivilegedAccounts'] = @(
    'DomainFqdn',
    'SamAccountName',
    'Name',
    'DistinguishedName',
    'ObjectClass',
    'Enabled',
    'PrivilegeGroups'
  )

  $schemas['Domain_Security_ServiceAccountCandidates'] = @(
    'DomainFqdn',
    'SamAccountName',
    'Name',
    'DistinguishedName',
    'UserPrincipalName',
    'PasswordLastSetUtc',
    'PasswordAgeDays',
    'LastLogonTimestampUtc',
    'LastLogonDays'
  )

  $schemas['Domain_Security_UsersSidHistory'] = @(
    'DomainFqdn',
    'SamAccountName',
    'Name',
    'DistinguishedName',
    'SidHistory'
  )

  $schemas['Domain_Security_OuDelegationAcls'] = @(
    'DomainFqdn',
    'OrganizationalUnitName',
    'OrganizationalUnitDn',
    'IdentityReference',
    'ActiveDirectoryRights',
    'AccessControlType',
    'ObjectType',
    'InheritanceType'
  )

  $schemas['Domain_Security_PasswordPolicyDefault'] = @(
    'DomainFqdn',
    'DistinguishedName',
    'MaxPasswordAge',
    'MinPasswordLength',
    'PasswordHistoryCount',
    'LockoutDuration',
    'LockoutObservationWindow',
    'LockoutThreshold',
    'ReversibleEncryption'
  )

  $schemas['Domain_Security_PasswordPolicyFgpp'] = @(
    'DomainFqdn',
    'Name',
    'DistinguishedName',
    'Precedence',
    'MaxPasswordAge',
    'MinPasswordLength',
    'PasswordHistoryCount',
    'LockoutDuration',
    'LockoutObservationWindow',
    'LockoutThreshold',
    'ReversibleEncryption'
  )

  $schemas['Domain_Security_PasswordPolicyFgppAssignments'] = @(
    'DomainFqdn',
    'FgppName',
    'FgppDn',
    'AssignedObjectName',
    'AssignedObjectDn',
    'AssignedObjectClass'
  )

  return $schemas
}
