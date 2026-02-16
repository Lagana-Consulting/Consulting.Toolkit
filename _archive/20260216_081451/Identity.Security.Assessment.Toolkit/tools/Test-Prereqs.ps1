<#
.SYNOPSIS
  Validates prerequisites for Identity Security Assessment Toolkit (AD + Entra/M365).

.DESCRIPTION
  Checks:
    - PowerShell version
    - RSAT AD module availability
    - Domain connectivity / basic AD queries
    - Microsoft Graph PowerShell SDK availability
    - Ability to acquire Graph access token
    - Optional: checks for key Graph permissions using "Get-MgContext" scopes

  This script is read-only.

.PARAMETER Domain
  Optional. A domain name to validate (used for informational output).

.PARAMETER TenantId
  Optional. Tenant ID or domain (e.g., contoso.onmicrosoft.com). Used for informational output.

.PARAMETER CheckGraph
  If set, performs Graph connection and scope checks.

.PARAMETER RequiredGraphScopes
  Scopes to request when connecting to Graph. If omitted, a sensible baseline is used.

.PARAMETER CheckBloodHoundTools
  If set, checks presence of SharpHound and BloodHound CE (paths are configurable below).

.EXAMPLE
  .\Test-Prereqs.ps1 -CheckGraph

.EXAMPLE
  .\Test-Prereqs.ps1 -Domain contoso.local -TenantId contoso.onmicrosoft.com -CheckGraph
#>

[CmdletBinding()]
param(
    [string]$Domain,
    [string]$TenantId,

    [switch]$CheckGraph,

    [string[]]$RequiredGraphScopes,

    [switch]$CheckBloodHoundTools
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Result {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )
    [pscustomobject]@{
        Check  = $Name
        Status = $Status  # PASS / WARN / FAIL
        Detail = $Detail
    }
}

$results = New-Object System.Collections.Generic.List[object]

# ----------------------------
# 1) PowerShell version checks
# ----------------------------
try {
    $psEdition = $PSVersionTable.PSEdition
    $psVer = $PSVersionTable.PSVersion.ToString()

    $results.Add((New-Result -Name 'PowerShell' -Status 'PASS' -Detail "PSEdition=$psEdition; Version=$psVer"))
} catch {
    $results.Add((New-Result -Name 'PowerShell' -Status 'FAIL' -Detail $_.Exception.Message))
}

# ---------------------------------
# 2) RSAT / ActiveDirectory module
# ---------------------------------
try {
    $adModule = Get-Module -ListAvailable -Name ActiveDirectory | Select-Object -First 1
    if (-not $adModule) {
        $results.Add((New-Result -Name 'RSAT ActiveDirectory module' -Status 'FAIL' -Detail 'ActiveDirectory module not found. Install RSAT: Active Directory PowerShell module.'))
    } else {
        $results.Add((New-Result -Name 'RSAT ActiveDirectory module' -Status 'PASS' -Detail "Found: $($adModule.Name) $($adModule.Version)"))
    }
} catch {
    $results.Add((New-Result -Name 'RSAT ActiveDirectory module' -Status 'FAIL' -Detail $_.Exception.Message))
}

# ----------------------------
# 3) Domain connectivity checks
# ----------------------------
try {
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory -ErrorAction Stop

        # Basic checks that should be read-only and low-impact
        $domainObj = Get-ADDomain -ErrorAction Stop
        $forestObj = Get-ADForest -ErrorAction Stop

        $dom = $domainObj.DNSRoot
        $for = $forestObj.Name

        $detail = "Connected to AD. Domain=$dom; Forest=$for"
        if ($Domain -and ($Domain -ne $dom)) {
            $detail += " (Note: -Domain provided '$Domain' differs from detected '$dom')"
        }

        $results.Add((New-Result -Name 'Active Directory connectivity' -Status 'PASS' -Detail $detail))

        # DC discovery
        $dcs = Get-ADDomainController -Filter * -ErrorAction Stop
        $results.Add((New-Result -Name 'Domain Controllers discovery' -Status 'PASS' -Detail "Found $($dcs.Count) domain controller(s)."))

        # Minimal sample query
        $sampleUser = Get-ADUser -Filter * -ResultSetSize 1 -Properties Enabled -ErrorAction Stop
        $results.Add((New-Result -Name 'AD sample query' -Status 'PASS' -Detail "Sample user query succeeded (returned 1 user)."))
    } else {
        $results.Add((New-Result -Name 'Active Directory connectivity' -Status 'WARN' -Detail 'Skipped (ActiveDirectory module not available).'))
    }
} catch {
    $results.Add((New-Result -Name 'Active Directory connectivity' -Status 'FAIL' -Detail $_.Exception.Message))
}

# ----------------------------
# 4) Graph SDK availability
# ----------------------------
try {
    $mgAuth = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Select-Object -First 1
    if (-not $mgAuth) {
        $results.Add((New-Result -Name 'Microsoft Graph PowerShell SDK' -Status 'FAIL' -Detail 'Microsoft.Graph.Authentication not found. Install Microsoft Graph PowerShell SDK.'))
    } else {
        $results.Add((New-Result -Name 'Microsoft Graph PowerShell SDK' -Status 'PASS' -Detail "Found: Microsoft.Graph.Authentication $($mgAuth.Version)"))
    }
} catch {
    $results.Add((New-Result -Name 'Microsoft Graph PowerShell SDK' -Status 'FAIL' -Detail $_.Exception.Message))
}

# ----------------------------
# 5) Graph connectivity & scope checks (optional)
# ----------------------------
if ($CheckGraph) {
    try {
        if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
            $results.Add((New-Result -Name 'Graph connect' -Status 'FAIL' -Detail 'Skipped: Graph SDK not installed.'))
        } else {
            Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

            # Baseline scopes if not provided
            if (-not $RequiredGraphScopes -or $RequiredGraphScopes.Count -eq 0) {
                $RequiredGraphScopes = @(
                    'Directory.Read.All',
                    'User.Read.All',
                    'Policy.Read.All'
                )
            }

            # Connect (delegated). Interactive auth by default.
            # If your client requires device code, you can switch to: Connect-MgGraph -Scopes $RequiredGraphScopes -UseDeviceAuthentication
            Connect-MgGraph -Scopes $RequiredGraphScopes -ErrorAction Stop | Out-Null

            $ctx = Get-MgContext
            $tenant = $ctx.TenantId
            $acct = $ctx.Account
            $scopesGranted = @($ctx.Scopes)

            $detail = "Connected. TenantId=$tenant; Account=$acct"
            if ($TenantId) {
                $detail += " (Note: -TenantId provided '$TenantId')"
            }
            $results.Add((New-Result -Name 'Graph connect' -Status 'PASS' -Detail $detail))

            # Scope check (best effort)
            $missing = @()
            foreach ($s in $RequiredGraphScopes) {
                if ($scopesGranted -notcontains $s) { $missing += $s }
            }

            if ($missing.Count -gt 0) {
                $results.Add((New-Result -Name 'Graph scopes' -Status 'WARN' -Detail ("Missing scopes in context: " + ($missing -join ', ') + ". This may indicate consent/policy limitations.")))
            } else {
                $results.Add((New-Result -Name 'Graph scopes' -Status 'PASS' -Detail ("All requested scopes present: " + ($RequiredGraphScopes -join ', '))))
            }

            # Optional quick read tests (low impact)
            Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
            $null = Get-MgUser -Top 1 -ErrorAction Stop
            $results.Add((New-Result -Name 'Graph sample query' -Status 'PASS' -Detail 'Get-MgUser -Top 1 succeeded.'))

            Disconnect-MgGraph | Out-Null
        }
    } catch {
        $results.Add((New-Result -Name 'Graph connect / checks' -Status 'FAIL' -Detail $_.Exception.Message))
        try { Disconnect-MgGraph | Out-Null } catch {}
    }
} else {
    $results.Add((New-Result -Name 'Graph connect' -Status 'WARN' -Detail 'Skipped (run with -CheckGraph to validate Graph auth/scopes).'))
}

# ----------------------------
# 6) Optional BloodHound tooling checks
# ----------------------------
if ($CheckBloodHoundTools) {
    try {
        # Adjust these paths to match how you distribute tools in-client
        $toolRoot = Join-Path $PSScriptRoot '..\tools'

        $sharpHoundCandidates = @(
            Join-Path $toolRoot 'SharpHound.exe',
            Join-Path $toolRoot 'SharpHound.ps1'
        ) | Where-Object { Test-Path $_ }

        if ($sharpHoundCandidates.Count -gt 0) {
            $results.Add((New-Result -Name 'SharpHound presence' -Status 'PASS' -Detail ("Found: " + ($sharpHoundCandidates -join '; '))))
        } else {
            $results.Add((New-Result -Name 'SharpHound presence' -Status 'WARN' -Detail 'Not found in tools/. Optional unless profile requires AD relationship analysis.'))
        }

        $bloodHoundCandidates = @(
            Join-Path $toolRoot 'BloodHound\BloodHound.exe'
        ) | Where-Object { Test-Path $_ }

        if ($bloodHoundCandidates.Count -gt 0) {
            $results.Add((New-Result -Name 'BloodHound CE presence' -Status 'PASS' -Detail ("Found: " + ($bloodHoundCandidates -join '; '))))
        } else {
            $results.Add((New-Result -Name 'BloodHound CE presence' -Status 'WARN' -Detail 'Not found in tools/. Optional unless profile requires local analysis UI.'))
        }
    } catch {
        $results.Add((New-Result -Name 'BloodHound tool checks' -Status 'FAIL' -Detail $_.Exception.Message))
    }
} else {
    $results.Add((New-Result -Name 'BloodHound tools' -Status 'WARN' -Detail 'Skipped (run with -CheckBloodHoundTools to validate optional tools).'))
}

# ----------------------------
# Output summary
# ----------------------------
$results |
Sort-Object Check |
Format-Table -AutoSize

# Exit code: FAIL => 1, else 0
if ($results.Status -contains 'FAIL') {
    Write-Host "`nOne or more prerequisite checks FAILED." -ForegroundColor Red
    exit 1
}

Write-Host "`nPrerequisite checks completed (no FAIL results)." -ForegroundColor Green
exit 0
