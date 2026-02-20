<#
.SYNOPSIS
Bootstraps an Entra app registration for M365 Discovery Collector (delegated + app-only certificate).

.DESCRIPTION
Creates or updates an app registration, ensures a service principal exists, applies Microsoft Graph
delegated and/or application permissions, attaches a certificate credential, and writes a local config
file consumable by Collector.App.

Recommended runtime: PowerShell 7.x.

.EXAMPLE
pwsh ./Setup-M365DiscoveryApp.ps1 -TenantId 623ad972-a938-44d6-9df8-54f9d0f6b09e -CreateSelfSignedCertificate

.EXAMPLE
pwsh ./Setup-M365DiscoveryApp.ps1 -TenantId 623ad972-a938-44d6-9df8-54f9d0f6b09e -ClientId cce6a7eb-a16c-4e48-8adc-00e159387306 -CertificateThumbprint <thumbprint>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter()]
    [string]$AppName = "M365 Discovery Collector",

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [switch]$CreateSelfSignedCertificate,

    [Parameter()]
    [ValidateSet("CurrentUser", "LocalMachine")]
    [string]$CertificateStoreLocation = "CurrentUser",

    [Parameter()]
    [string]$CertificateDnsName = "m365-discovery-collector",

    [Parameter()]
    [ValidateRange(1, 5)]
    [int]$CertificateYears = 2,

    [Parameter()]
    [bool]$IncludeApplicationPermissions = $true,

    [Parameter()]
    [bool]$IncludeDelegatedPermissions = $true,

    [Parameter()]
    [string]$OutputConfigPath = ".\m365-discovery-auth-config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "PowerShell 7+ is recommended for cloud setup automation. Current version: $($PSVersionTable.PSVersion)"
}

function Ensure-MgModule {
    $required = @(
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.Applications"
    )
    foreach ($m in $required) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            throw "Required module '$m' is not installed. Install with: Install-Module $m -Scope CurrentUser"
        }
    }
}

function Get-CertificateFromStore {
    param(
        [Parameter(Mandatory)][string]$Thumbprint
    )
    $normalized = $Thumbprint.Replace(" ", "").ToUpperInvariant()
    $stores = @("Cert:\CurrentUser\My", "Cert:\LocalMachine\My")
    foreach ($store in $stores) {
        $cert = Get-ChildItem -Path $store | Where-Object { $_.Thumbprint -eq $normalized } | Select-Object -First 1
        if ($cert) { return $cert }
    }
    throw "Certificate with thumbprint '$Thumbprint' not found in CurrentUser/My or LocalMachine/My."
}

function New-CollectorCertificate {
    param(
        [Parameter(Mandatory)][string]$DnsName,
        [Parameter(Mandatory)][string]$StoreLocation,
        [Parameter(Mandatory)][int]$Years
    )
    $storePath = "Cert:\$StoreLocation\My"
    $cert = New-SelfSignedCertificate `
        -DnsName $DnsName `
        -CertStoreLocation $storePath `
        -NotAfter (Get-Date).AddYears($Years) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -KeyExportPolicy Exportable `
        -HashAlgorithm SHA256
    return $cert
}

function Get-GraphPermissionResourceAccess {
    param(
        [Parameter(Mandatory)][object]$GraphServicePrincipal,
        [Parameter(Mandatory)][string[]]$PermissionValues,
        [Parameter(Mandatory)][bool]$UseDelegated,
        [Parameter(Mandatory)][bool]$UseApplication
    )

    $access = @()
    foreach ($perm in $PermissionValues) {
        if ($UseDelegated) {
            $scope = $GraphServicePrincipal.oauth2PermissionScopes |
            Where-Object { $_.Value -eq $perm -and $_.IsEnabled } |
            Select-Object -First 1
            if ($scope) {
                $access += @{ id = $scope.Id; type = "Scope" }
            } else {
                Write-Warning "Delegated permission not found or disabled: $perm"
            }
        }

        if ($UseApplication) {
            $role = $GraphServicePrincipal.appRoles |
            Where-Object { $_.Value -eq $perm -and $_.IsEnabled -and ($_.AllowedMemberTypes -contains "Application") } |
            Select-Object -First 1
            if ($role) {
                $access += @{ id = $role.Id; type = "Role" }
            } else {
                Write-Warning "Application permission not found or disabled: $perm"
            }
        }
    }

    return $access
}

function Merge-RequiredResourceAccess {
    param(
        [Parameter(Mandatory)][array]$Existing,
        [Parameter(Mandatory)][string]$ResourceAppId,
        [Parameter(Mandatory)][array]$NewAccess
    )

    $combined = @($Existing)
    $target = $combined | Where-Object { $_.resourceAppId -eq $ResourceAppId } | Select-Object -First 1
    if (-not $target) {
        $combined += @{
            resourceAppId  = $ResourceAppId
            resourceAccess = @($NewAccess)
        }
        return $combined
    }

    $existingSet = @($target.resourceAccess)
    foreach ($a in $NewAccess) {
        $exists = $existingSet | Where-Object { $_.id -eq $a.id -and $_.type -eq $a.type } | Select-Object -First 1
        if (-not $exists) {
            $existingSet += $a
        }
    }
    $target.resourceAccess = $existingSet
    return $combined
}

Write-Host "== M365 Discovery Collector App Setup ==" -ForegroundColor Cyan
Ensure-MgModule

Connect-MgGraph -TenantId $TenantId -Scopes @(
    "Application.ReadWrite.All",
    "AppRoleAssignment.ReadWrite.All",
    "Directory.Read.All"
) -NoWelcome | Out-Null

$context = Get-MgContext
Write-Host "Connected tenant: $($context.TenantId)" -ForegroundColor Gray

$graphSp = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'" `
| Select-Object -ExpandProperty value | Select-Object -First 1
if (-not $graphSp) { throw "Microsoft Graph service principal not found." }

if ($CreateSelfSignedCertificate -and $CertificateThumbprint) {
    throw "Specify either -CreateSelfSignedCertificate or -CertificateThumbprint, not both."
}

if ($CreateSelfSignedCertificate) {
    $cert = New-CollectorCertificate -DnsName $CertificateDnsName -StoreLocation $CertificateStoreLocation -Years $CertificateYears
    $CertificateThumbprint = $cert.Thumbprint
    Write-Host "Created certificate: $($cert.Thumbprint) ($CertificateStoreLocation\My)" -ForegroundColor Green
} elseif ($CertificateThumbprint) {
    $cert = Get-CertificateFromStore -Thumbprint $CertificateThumbprint
    Write-Host "Using certificate: $($cert.Thumbprint)" -ForegroundColor Green
} else {
    throw "Provide -CertificateThumbprint or use -CreateSelfSignedCertificate."
}

$permissions = @(
    "User.Read.All",
    "Group.Read.All",
    "Application.Read.All",
    "Directory.Read.All",
    "Organization.Read.All",
    "Policy.Read.All",
    "Reports.Read.All",
    "AuditLog.Read.All"
)

$resourceAccess = Get-GraphPermissionResourceAccess `
    -GraphServicePrincipal $graphSp `
    -PermissionValues $permissions `
    -UseDelegated:$IncludeDelegatedPermissions `
    -UseApplication:$IncludeApplicationPermissions

if (-not $resourceAccess -or $resourceAccess.Count -eq 0) {
    throw "No resource access entries were resolved from requested permissions."
}

$resolvedScopes = @($resourceAccess | Where-Object { $_.type -eq "Scope" })
$resolvedRoles = @($resourceAccess | Where-Object { $_.type -eq "Role" })

Write-Host "Resolved Graph permissions:" -ForegroundColor Gray
Write-Host "  Delegated scopes: $($resolvedScopes.Count)"
Write-Host "  Application roles: $($resolvedRoles.Count)"

if ($IncludeApplicationPermissions -and $resolvedRoles.Count -eq 0) {
    throw "Application permissions were requested but no Graph app roles were resolved. Check Graph service principal role availability and permission names."
}

$app = $null
if ($ClientId) {
    $existing = Invoke-MgGraphRequest -Method GET -Uri "v1.0/applications?`$filter=appId eq '$ClientId'" |
    Select-Object -ExpandProperty value | Select-Object -First 1
    if (-not $existing) { throw "No application found for ClientId '$ClientId'." }
    $app = $existing
    Write-Host "Updating existing app: $($app.displayName) ($($app.appId))" -ForegroundColor Yellow
} else {
    $body = @{
        displayName            = $AppName
        signInAudience         = "AzureADMyOrg"
        isFallbackPublicClient = $true
        publicClient           = @{ redirectUris = @("http://localhost") }
        requiredResourceAccess = @(
            @{
                resourceAppId  = "00000003-0000-0000-c000-000000000000"
                resourceAccess = @($resourceAccess)
            }
        )
        keyCredentials         = @(
            @{
                type          = "AsymmetricX509Cert"
                usage         = "Verify"
                key           = [Convert]::ToBase64String($cert.RawData)
                displayName   = "M365DiscoveryCert"
                startDateTime = $cert.NotBefore.ToUniversalTime().ToString("o")
                endDateTime   = $cert.NotAfter.ToUniversalTime().ToString("o")
            }
        )
    }

    $app = Invoke-MgGraphRequest -Method POST -Uri "v1.0/applications" -Body ($body | ConvertTo-Json -Depth 10) -ContentType "application/json"
    Write-Host "Created app registration: $($app.displayName) ($($app.appId))" -ForegroundColor Green
}

if ($ClientId) {
    $merged = Merge-RequiredResourceAccess `
        -Existing @($app.requiredResourceAccess) `
        -ResourceAppId "00000003-0000-0000-c000-000000000000" `
        -NewAccess @($resourceAccess)

    $patchBody = @{
        requiredResourceAccess = @($merged)
        keyCredentials         = @(
            @($app.keyCredentials)
            @{
                type          = "AsymmetricX509Cert"
                usage         = "Verify"
                key           = [Convert]::ToBase64String($cert.RawData)
                displayName   = "M365DiscoveryCert"
                startDateTime = $cert.NotBefore.ToUniversalTime().ToString("o")
                endDateTime   = $cert.NotAfter.ToUniversalTime().ToString("o")
            }
        )
    }
    Invoke-MgGraphRequest -Method PATCH -Uri "v1.0/applications/$($app.id)" -Body ($patchBody | ConvertTo-Json -Depth 10) -ContentType "application/json" | Out-Null
}

$sp = Invoke-MgGraphRequest -Method GET -Uri "v1.0/servicePrincipals?`$filter=appId eq '$($app.appId)'" |
Select-Object -ExpandProperty value | Select-Object -First 1
if (-not $sp) {
    $sp = Invoke-MgGraphRequest -Method POST -Uri "v1.0/servicePrincipals" -Body (@{appId = $app.appId } | ConvertTo-Json) -ContentType "application/json"
    Write-Host "Created service principal." -ForegroundColor Green
}

$consentUrl = "https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$($app.appId)&redirect_uri=$([uri]::EscapeDataString('http://localhost'))"

$configOut = @{
    ClientId                    = $app.appId
    TenantId                    = $TenantId
    UseAppOnlyCertificateSignIn = $true
    CertificateThumbprint       = $cert.Thumbprint
    CertificateSubjectName      = $cert.Subject
    AdminConsentUrl             = $consentUrl
} | ConvertTo-Json -Depth 5

$configDir = Split-Path -Parent $OutputConfigPath
if ($configDir -and -not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}
$configOut | Set-Content -Path $OutputConfigPath

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host "Client ID: $($app.appId)"
Write-Host "Tenant ID: $TenantId"
Write-Host "Certificate Thumbprint: $($cert.Thumbprint)"
Write-Host "Config file: $OutputConfigPath"
Write-Host "Admin consent URL:"
Write-Host "  $consentUrl"
Write-Host ""
Write-Host "Next:"
Write-Host "1) Grant admin consent using the URL above."
Write-Host "2) In Collector.App, set sign-in mode to app-only certificate."
Write-Host "3) Paste Tenant ID + Thumbprint and sign in."
