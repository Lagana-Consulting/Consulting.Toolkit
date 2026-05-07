# Migration.Toolkit.Preparation

`Migration.Toolkit.Preparation` is an internal module for checking and applying
ADMT-oriented prerequisites in source and target Active Directory environments.

The module is intentionally config-driven. It can test prerequisites, emit
CSV/JSON evidence, and apply concrete settings such as registry values, service
state, configured AD service accounts, configured group memberships, and selected
trust flags.

## Quick Start

Import the module:

```powershell
Import-Module "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Preparation\Migration.Toolkit.Preparation.psd1" -Force
```

Run in the source environment:

```powershell
Test-AdmtPrerequisite `
  -Role Source `
  -OutputRoot "C:\Temp\AdmtPreparation"
```

Run in the target environment:

```powershell
Test-AdmtPrerequisite `
  -Role Target `
  -OutputRoot "C:\Temp\AdmtPreparation"
```

Preview fixes:

```powershell
Invoke-AdmtPreparation `
  -Role Source `
  -OutputRoot "C:\Temp\AdmtPreparation" `
  -WhatIf
```

Apply configured fixes:

```powershell
Invoke-AdmtPreparation `
  -Role Source `
  -OutputRoot "C:\Temp\AdmtPreparation"
```

Apply service-account creation rules:

```powershell
$password = Read-Host "ADMT service account password" -AsSecureString

Invoke-AdmtPreparation `
  -Role Source `
  -ConfigPath "C:\Temp\AdmtPreparation.Source.json" `
  -ServiceAccountPassword $password `
  -OutputRoot "C:\Temp\AdmtPreparation"
```

You can also use the wrapper script:

```powershell
& "C:\Users\paull\OneDrive - Lagana Consulting\Documents\GitHub\Consulting.Toolkit\src\Migration.Toolkit.Preparation\Public\run-preparation.ps1" `
  -Role Source `
  -OutputRoot "C:\Temp\AdmtPreparation"
```

## Commands

- `Test-AdmtPrerequisite`
- `Invoke-AdmtPreparation`
- `New-AdmtPreparationReport`

## Default Checks

Source environment:

- `TcpipClientSupport` registry value under `HKLM:\SYSTEM\CurrentControlSet\Control\Lsa`
- `RemoteRegistry` service status and startup type
- Active Directory PowerShell module availability
- current domain readability
- configured source ADMT service account existence, enabled state, and required group memberships
- configured trust relationship to the target domain
- configured DNS resolution for target-domain names
- manual checkpoints for ADMT-related group/access validation

Target environment:

- Active Directory PowerShell module availability
- current domain readability
- configured target ADMT service account existence, enabled state, and required group memberships
- configured trust relationship to the source domain
- configured DNS resolution for source-domain names
- manual checkpoints for ADMT-related group/access validation

## Custom Rules

Copy `config\AdmtPreparationRules.Standard.json`, edit it, and pass the copy with
`-ConfigPath`.

Example group member rule:

```json
{
  "Name": "Administrators",
  "Members": [ "CONTOSO\\admt-svc" ],
  "Severity": "Fail",
  "Recommendation": "The ADMT migration account must be a member for this migration design."
}
```

Example service account rules:

```json
{
  "Source": {
    "ServiceAccounts": [
      {
        "Name": "Source ADMT service account",
        "SamAccountName": "admt-src-svc",
        "UserPrincipalName": "admt-src-svc@source.contoso.com",
        "CreateIfMissing": true,
        "Path": "OU=Service Accounts,DC=source,DC=contoso,DC=com",
        "Enabled": true,
        "PasswordNeverExpires": true,
        "Description": "ADMT source-side migration service account.",
        "RequiredGroups": [
          "Domain Admins",
          "Pre-Windows 2000 Compatible Access"
        ],
        "Severity": "Fail",
        "Recommendation": "Create or enable the source ADMT service account and add it to the required source-domain groups."
      }
    ]
  },
  "Target": {
    "ServiceAccounts": [
      {
        "Name": "Target ADMT service account",
        "SamAccountName": "admt-tgt-svc",
        "UserPrincipalName": "admt-tgt-svc@target.contoso.com",
        "CreateIfMissing": true,
        "Path": "OU=Service Accounts,DC=target,DC=contoso,DC=com",
        "Enabled": true,
        "PasswordNeverExpires": true,
        "Description": "ADMT target-side migration service account.",
        "RequiredGroups": [
          "Domain Admins",
          "Administrators"
        ],
        "Severity": "Fail",
        "Recommendation": "Create or enable the target ADMT service account and add it to the required target-domain groups."
      }
    ]
  }
}
```

`Test-AdmtPrerequisite` verifies that configured service accounts exist, are
enabled, and belong to each listed `RequiredGroups` entry. `Invoke-AdmtPreparation`
can create missing service accounts only when `CreateIfMissing` is `true` and
`-ServiceAccountPassword` is supplied. It also adds missing configured group
memberships for the account.

Example trust and DNS rules:

```json
{
  "Source": {
    "Trusts": [
      {
        "Name": "Source to target trust",
        "TargetDomain": "target.contoso.com",
        "ExpectedDirection": "Bidirectional",
        "ExpectedTrustType": "",
        "RequireTransitive": null,
        "RequireSidFilteringQuarantined": false,
        "RequireSelectiveAuthentication": null,
        "Severity": "Fail",
        "Recommendation": "Confirm the source domain has the expected ADMT trust configuration to the target domain."
      }
    ],
    "DnsResolution": [
      {
        "Name": "Resolve target domain",
        "HostName": "target.contoso.com",
        "RecordType": "A",
        "ExpectedAddresses": [],
        "DnsServer": "",
        "Severity": "Fail",
        "Recommendation": "Confirm source DNS can resolve the target domain."
      }
    ]
  },
  "Target": {
    "Trusts": [
      {
        "Name": "Target to source trust",
        "TargetDomain": "source.contoso.com",
        "ExpectedDirection": "Bidirectional",
        "ExpectedTrustType": "",
        "RequireTransitive": null,
        "RequireSidFilteringQuarantined": false,
        "RequireSelectiveAuthentication": null,
        "Severity": "Fail",
        "Recommendation": "Confirm the target domain has the expected ADMT trust configuration to the source domain."
      }
    ],
    "DnsResolution": [
      {
        "Name": "Resolve source domain",
        "HostName": "source.contoso.com",
        "RecordType": "A",
        "ExpectedAddresses": [],
        "DnsServer": "",
        "Severity": "Fail",
        "Recommendation": "Confirm target DNS can resolve the source domain."
      }
    ]
  }
}
```

For DNS checks, leave `ExpectedAddresses` empty when any successful answer is
acceptable. Add one or more IP addresses when the answer must match known domain
controllers, VIPs, or conditional-forwarder targets. Set `DnsServer` when you
need to query a specific resolver instead of the machine default.

`Invoke-AdmtPreparation` applies `RequireSidFilteringQuarantined` and
`RequireSelectiveAuthentication` when those values are not `null` and the local
Active Directory module exposes the matching `Set-ADTrust` parameters. It does
not create trusts, change trust direction/type, or change trust transitivity.

Always run `Invoke-AdmtPreparation -WhatIf` before applying changes in a domain
environment.
