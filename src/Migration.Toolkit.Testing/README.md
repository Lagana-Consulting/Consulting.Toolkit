# Migration.Toolkit.Testing

`Migration.Toolkit.Testing` contains lab-only helpers for testing migration
workflows against realistic Active Directory data.

## Seed a Lab Domain

Import the module:

```powershell
Import-Module "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Testing\Migration.Toolkit.Testing.psd1" -Force
```

Preview a small seed from discovery output:

```powershell
New-AdMigrationLabSeed `
  -RunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -StagingOuName "Migration Lab Staging" `
  -UserLimit 25 `
  -GroupLimit 25 `
  -WhatIf
```

Build a plan without requiring RSAT or a live AD connection:

```powershell
New-AdMigrationLabSeed `
  -RunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -StagingBaseDn "DC=lab,DC=local" `
  -UserLimit 25 `
  -GroupLimit 25 `
  -PlanOnly `
  -OutputPath "C:\Temp\MigrationLabSeed-Plan.csv"
```

Apply it:

```powershell
New-AdMigrationLabSeed `
  -RunRoot "F:\Shared\AD_sourcelab.com_20260423-082040" `
  -StagingOuName "Migration Lab Staging" `
  -UserLimit 25 `
  -GroupLimit 25 `
  -OutputPath "C:\Temp\MigrationLabSeed.csv"
```

The command creates:

- `OU=<StagingOuName>` under the current lab domain root, unless `-StagingBaseDn`
  is supplied
- one OU per source domain under the staging OU
- source OU/container paths beneath the source-domain OU
- groups from `AD__Domain__Identity__Groups__*.csv`
- users from `AD__Domain__Identity__Users__*.csv`

Groups are created before users. Existing users/groups with the same
`sAMAccountName` are skipped.

Built-in/default groups and users are skipped by default. Use
`-IncludeBuiltInGroups` or `-IncludeBuiltInUsers` only when you intentionally
want staged lab copies of those objects.

Create failures are written to the result and optional CSV as `Action = Failed`
so one bad discovery row does not stop the whole lab seed. Add `-StopOnError`
when troubleshooting a specific failure and you want the original exception.

Use `-CreateDisabledUsers` to create all users disabled. Otherwise the script
uses the discovered `Enabled` value. The default password is only for lab use and
can be changed with `-DefaultPassword`.
