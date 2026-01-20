function Get-LcSchemaDefinitions {
  [CmdletBinding()]
  param()

  # Return: hashtable of SchemaName -> string[] Columns
  # Start with the datasets you know you will always produce first.

  $schemas = @{}

  $schemas['Forest_Summary'] = @(
    'ForestName',
    'RootDomain',
    'Domains',
    'UPNSuffixes',
    'ForestMode',
    'SchemaMaster',
    'DomainNamingMaster'
  )

  $schemas['Forest_UPNSuffixes'] = @(
    'Suffix',
    'IsKnownSuffix',
    'IsNonRoutable'
  )

  $schemas['Domain_Summary'] = @(
    'DomainFqdn',
    'DomainDn',
    'NetBIOSName',
    'DomainMode',
    'PdcEmulator',
    'RidMaster',
    'InfrastructureMaster'
  )

  $schemas['AD_Users'] = @(
    'Domain',
    'SamAccountName',
    'UserPrincipalName',
    'UPNSuffix',
    'IsNonRoutableUpnSuffix',
    'Enabled',
    'WhenCreated',
    'LastLogonTimestamp',
    'LastLogonDays',
    'PasswordLastSet',
    'PasswordAgeDays',
    'AdminCount',
    'SidHistoryCount',
    'SPNCount',
    'MsDsSupportedEncryptionTypes',
    'EncryptionTypes',
    'EncryptionRisk'
  )

  $schemas['AD_Computers'] = @(
    'Domain',
    'Name',
    'DnsHostName',
    'OperatingSystem',
    'IsServer',
    'Enabled',
    'WhenCreated',
    'LastLogonTimestamp',
    'LastLogonDays',
    'MsDsSupportedEncryptionTypes',
    'EncryptionTypes',
    'EncryptionRisk'
  )

  $schemas['AD_RiskFlags'] = @(
    'Scope',          # Forest/Domain/User/Computer/Group/GPO/etc
    'Domain',
    'ObjectType',
    'ObjectName',
    'ObjectId',       # DN or GUID or SID
    'RiskCategory',
    'RiskName',
    'RiskLevel',      # Low/Medium/High
    'Details'
  )

  return $schemas
}
