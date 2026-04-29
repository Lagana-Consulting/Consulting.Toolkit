function Get-AdPrivilegedGroupNames {
  [CmdletBinding()]
  param()

  # Domain-local names; you can extend per client.
  return @(
    'Enterprise Admins',
    'Domain Admins',
    'Schema Admins',
    'Administrators',
    'Account Operators',
    'Server Operators',
    'Backup Operators',
    'Print Operators',
    'Group Policy Creator Owners'
  )
}
