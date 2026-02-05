#!/usr/bin/env powershell
<#
.SYNOPSIS
Automated setup script for cloud discovery service principal and certificate.

.DESCRIPTION
Creates Azure AD application registration, configures API permissions, generates certificate,
and saves configuration for use with Migration.Toolkit.Cloud module.

Requires Global Admin or Cloud App Admin role in Azure AD.

.PARAMETER TenantId
Azure AD tenant ID or domain name (e.g., contoso.onmicrosoft.com).

.PARAMETER ApplicationName
Display name for service principal. Default "Cloud Discovery Service Principal".

.PARAMETER CertificatePath
Output path for .pfx certificate. Default "$env:TEMP\cloud-discovery.pfx".

.PARAMETER CertificateValidityYears
Validity period for self-signed cert. Default 2 years.

.PARAMETER PermissionsLevel
Permissions to grant: 'Minimal' or 'Extended'. Default 'Extended'.

.EXAMPLE
.\Setup-CloudDiscoveryServicePrincipal.ps1 -TenantId "contoso.onmicrosoft.com"

Creates service principal and certificate, saves config to local directory.

.NOTES
Requires:
- Global Admin or Cloud App Admin role
- Microsoft.Graph.Applications module
- PowerShell 5.1+

This script:
1. Creates Azure AD application registration
2. Generates self-signed certificate
3. Uploads certificate to Azure AD
4. Assigns API permissions
5. Saves configuration file for use with cloud discovery module
#>

param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [string]$ApplicationName = "Quest Discovery Service Principal",

    [string]$CertificatePath = (Join-Path $env:TEMP "cloud-discovery.pfx"),

    [int]$CertificateValidityYears = 2,

    [ValidateSet('Minimal', 'Extended')]
    [string]$PermissionsLevel = 'Extended'
)

#Requires -Modules Microsoft.Graph.Applications, Microsoft.Graph.Authentication

$ErrorActionPreference = 'Stop'

Write-Host "=== Cloud Discovery Service Principal Setup ===" -ForegroundColor Green
Write-Host ""

# Connect to Graph
Write-Host "Connecting to Azure AD tenant: $TenantId" -ForegroundColor Yellow
try {
    Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All" -ErrorAction Stop
    Write-Host "✓ Connected" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to connect. Ensure you have Global Admin role." -ForegroundColor Red
    throw
}

# Create application registration
Write-Host ""
Write-Host "Creating application registration: $ApplicationName" -ForegroundColor Yellow
$app = New-MgApplication -DisplayName $ApplicationName `
    -SignInAudience "AzureADMyOrg" `
    -Description "Service principal for automated cloud workload discovery via Migration.Toolkit.Cloud" `
    -ErrorAction Stop

Write-Host "✓ Application created" -ForegroundColor Green
Write-Host "  Application ID: $($app.AppId)" -ForegroundColor Cyan
Write-Host "  Object ID: $($app.Id)" -ForegroundColor Cyan

# Create service principal
Write-Host ""
Write-Host "Creating service principal..." -ForegroundColor Yellow
$sp = New-MgServicePrincipal -AppId $app.AppId -AccountEnabled $true -ErrorAction Stop
Write-Host "✓ Service principal created" -ForegroundColor Green

# Generate certificate
Write-Host ""
Write-Host "Generating self-signed certificate valid for $CertificateValidityYears years..." -ForegroundColor Yellow
$cert = New-SelfSignedCertificate `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -Subject "CN=$ApplicationName" `
    -KeyUsage DigitalSignature `
    -Type CodeSigningCert `
    -NotAfter (Get-Date).AddYears($CertificateValidityYears) `
    -HashAlgorithm SHA256 `
    -ErrorAction Stop

Write-Host "✓ Certificate generated" -ForegroundColor Green
Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Cyan
Write-Host "  Valid from: $($cert.NotBefore)" -ForegroundColor Cyan
Write-Host "  Valid until: $($cert.NotAfter)" -ForegroundColor Cyan

# Export certificate to .pfx
Write-Host ""
Write-Host "Exporting certificate to .pfx..." -ForegroundColor Yellow
$certPassword = Read-Host "Enter password to encrypt certificate" -AsSecureString
$securePassword = ConvertTo-SecureString -String ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($certPassword))) -AsPlainText -Force

Export-PfxCertificate -Cert $cert `
    -FilePath $CertificatePath `
    -Password $securePassword `
    -ErrorAction Stop | Out-Null

Write-Host "✓ Certificate exported to: $CertificatePath" -ForegroundColor Green

# Upload certificate to Azure AD
Write-Host ""
Write-Host "Uploading certificate to Azure AD application..." -ForegroundColor Yellow
$keyCredential = @{
    type        = "AsymmetricX509Cert"
    usage       = "Sign"
    key         = [System.Convert]::ToBase64String($cert.RawData)
    displayName = "Cloud Discovery Cert - Expires $($cert.NotAfter.ToString('yyyy-MM-dd'))"
}

Update-MgApplication -ApplicationId $app.Id -KeyCredentials @($keyCredential) -ErrorAction Stop | Out-Null
Write-Host "✓ Certificate uploaded to Azure AD" -ForegroundColor Green

# Define permissions based on level
Write-Host ""
Write-Host "Assigning API permissions (Level: $PermissionsLevel)..." -ForegroundColor Yellow

$msGraphId = "00000003-0000-0000-c000-000000000000"

$permissionsMap = @{
    'Minimal'  = @(
        @{ name = "User.Read.All"; id = "df021288-bdef-4463-88db-98f22db89214" }
        @{ name = "Group.Read.All"; id = "5b567255-7703-4780-807c-7be8301ae99b" }
        @{ name = "Directory.Read.All"; id = "3eca3a1a-cb31-4236-b4b4-e3d4ce2c34e5" }
        @{ name = "Mail.Read"; id = "810c84a8-4a9e-49e6-bf7d-12d183f40d01" }
        @{ name = "Sites.Read.All"; id = "205e0cdc-aba3-45b9-bdab-ef04442e4868" }
        @{ name = "Team.ReadBasic.All"; id = "2497278f-e461-46a7-ba8e-66aca8a78fa8" }
    )
    'Extended' = @(
        @{ name = "User.Read.All"; id = "df021288-bdef-4463-88db-98f22db89214" }
        @{ name = "Group.Read.All"; id = "5b567255-7703-4780-807c-7be8301ae99b" }
        @{ name = "Device.Read.All"; id = "7438b122-aefc-4978-9f5f-8824cb56b53d" }
        @{ name = "Directory.Read.All"; id = "3eca3a1a-cb31-4236-b4b4-e3d4ce2c34e5" }
        @{ name = "Application.Read.All"; id = "9a5d68fd-3437-4249-883e-5d3a9c20f801" }
        @{ name = "Mail.Read"; id = "810c84a8-4a9e-49e6-bf7d-12d183f40d01" }
        @{ name = "Calendar.Read.All"; id = "ef54d2bf-783f-4e0f-bca1-3210c0444d99" }
        @{ name = "Sites.Read.All"; id = "205e0cdc-aba3-45b9-bdab-ef04442e4868" }
        @{ name = "SharePointTenantSettings.Read.All"; id = "20f50933-e211-4295-a72f-1f4f47b0b2da" }
        @{ name = "DriveSettings.Read.All"; id = "5c6e2ac6-552b-41f9-8084-b6c5e87d1f82" }
        @{ name = "Team.ReadBasic.All"; id = "2497278f-e461-46a7-ba8e-66aca8a78fa8" }
        @{ name = "TeamSettings.Read.All"; id = "cd87405c-5792-4f91-83ea-5a87ee1d6fb7" }
        @{ name = "Reports.Read.All"; id = "230c1aed-57a9-4d5e-b2d3-d3ce0167b87f" }
        @{ name = "AuditLog.Read.All"; id = "e4006b1e-06b6-4b58-b986-d3a6c67f258d" }
    )
}

$selectedPerms = $permissionsMap[$PermissionsLevel]

foreach ($perm in $selectedPerms) {
    try {
        $appRole = @{
            origin = "Application"
            id     = $perm.id
            type   = "Role"
        }

        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id `
            -AppRoleId $perm.id `
            -ResourceId (Get-MgServicePrincipal -Filter "appId eq '$msGraphId'" | Select-Object -ExpandProperty Id) `
            -PrincipalId $sp.Id `
            -ErrorAction SilentlyContinue | Out-Null

        Write-Host "  ✓ $($perm.name)" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed to assign $($perm.name): $_" -ForegroundColor Yellow
    }
}

# Save configuration
Write-Host ""
Write-Host "Saving configuration..." -ForegroundColor Yellow

$config = @{
    TenantId              = $TenantId
    ApplicationId         = $app.AppId
    ApplicationObjectId   = $app.Id
    ServicePrincipalId    = $sp.Id
    CertificateThumbprint = $cert.Thumbprint
    CertificatePath       = $CertificatePath
    CertificateValidUntil = $cert.NotAfter
    PermissionsLevel      = $PermissionsLevel
    CreatedAt             = Get-Date -AsUTC
    Note                  = "Use Connect-AdCloudTenant with -ClientId $($app.AppId) -CertificatePath '$CertificatePath' -CertificatePassword <secure_password>"
} | ConvertTo-Json

$configPath = Join-Path (Get-Location) "CloudDiscovery_ServicePrincipal_Config.json"
$config | Out-File -FilePath $configPath -Encoding UTF8 -Force

Write-Host "✓ Configuration saved to: $configPath" -ForegroundColor Green

# Final instructions
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Store certificate password securely (e.g., Azure Key Vault, credential manager)"
Write-Host "2. Move $CertificatePath to secure location on your servers"
Write-Host "3. Update CloudDiscovery_ServicePrincipal_Config.json with correct paths"
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "  Import-Module Migration.Toolkit.Cloud"
Write-Host "  Connect-AdCloudTenant -TenantId '$TenantId' -ClientId '$($app.AppId)' \"
Write-Host "    -CertificatePath '$CertificatePath' -CertificatePassword \`$securePassword"
Write-Host "  Invoke-AdCloudDiscovery -OutputRoot 'C:\Reports' -Workloads All"
Write-Host ""
Write-Host "Documentation:" -ForegroundColor Yellow
Write-Host "  See SETUP_GUIDE.md for detailed configuration instructions"
Write-Host ""

Write-Host "Configuration Details:" -ForegroundColor Cyan
Write-Host $config
