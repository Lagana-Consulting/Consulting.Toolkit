<#
.SYNOPSIS
Checks for and installs required PowerShell modules for Migration.Toolkit.Cloud.

.DESCRIPTION
Validates and installs all prerequisite modules needed for cloud workload discovery:
- Microsoft Graph SDK modules (for Entra ID, Teams, SharePoint, OneDrive)
- Exchange Online Management module (for Exchange Online discovery)

Supports both interactive installation and automated deployment scenarios.
Can check versions, update existing modules, or perform clean installation.

.PARAMETER Scope
Installation scope: 'CurrentUser' or 'AllUsers'. Default 'CurrentUser'.
AllUsers requires elevated (admin) PowerShell session.

.PARAMETER Force
Force reinstallation even if modules are already present. Useful for upgrades.

.PARAMETER MinimumVersion
Minimum acceptable version for modules. Default '2.0.0' for Graph, '3.0.0' for Exchange.

.PARAMETER SkipExchange
Skip Exchange Online Management module installation. Use if only Entra/Teams/SharePoint discovery needed.

.PARAMETER CheckOnly
Only check current state without installing. Reports what would be installed.

.EXAMPLE
.\Install-CloudDiscoveryPrerequisites.ps1

Checks and installs all required modules for current user (interactive).

.EXAMPLE
.\Install-CloudDiscoveryPrerequisites.ps1 -Scope AllUsers

Installs modules for all users (requires admin rights).

.EXAMPLE
.\Install-CloudDiscoveryPrerequisites.ps1 -CheckOnly

Reports current module versions without installing.

.EXAMPLE
.\Install-CloudDiscoveryPrerequisites.ps1 -Force -MinimumVersion "2.10.0"

Forces reinstall of all modules with minimum version 2.10.0.

.NOTES
Requires internet connectivity to download from PowerShell Gallery.
For AllUsers scope, run PowerShell as Administrator.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$Force,

    [version]$MinimumVersion = '2.0.0',

    [switch]$SkipExchange,

    [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Required Microsoft Graph SDK modules
$graphModules = @(
    'Microsoft.Graph.Authentication'
    'Microsoft.Graph.Users'
    'Microsoft.Graph.Groups'
    'Microsoft.Graph.DeviceManagement'
    'Microsoft.Graph.Mail'
    'Microsoft.Graph.Teams'
    'Microsoft.Graph.Sites'
    'Microsoft.Graph.Files'
    'Microsoft.Graph.Applications'
    'Microsoft.Graph.Identity.DirectoryManagement'
    'Microsoft.Graph.Reports'
)

# Exchange Online module (different versioning)
$exchangeModule = 'ExchangeOnlineManagement'
$exchangeMinVersion = [version]'3.0.0'

# Color output helpers
function Write-Status {
    param([string]$Message, [string]$Type = 'Info')
    switch ($Type) {
        'Success' { Write-Host "✓ $Message" -ForegroundColor Green }
        'Warning' { Write-Host "⚠ $Message" -ForegroundColor Yellow }
        'Error' { Write-Host "✗ $Message" -ForegroundColor Red }
        'Info' { Write-Host "ℹ $Message" -ForegroundColor Cyan }
        default { Write-Host $Message }
    }
}

function Write-SectionHeader {
    param([string]$Title)
    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
}

# Check if running as admin (needed for AllUsers scope)
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Get module info (installed version)
function Get-ModuleStatus {
    param([string]$ModuleName, [version]$RequiredVersion)

    $installed = Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending | Select-Object -First 1

    if ($installed) {
        $meetsRequirement = $installed.Version -ge $RequiredVersion
        return @{
            Name             = $ModuleName
            Installed        = $true
            Version          = $installed.Version
            MeetsRequirement = $meetsRequirement
            RequiredVersion  = $RequiredVersion
        }
    }
    else {
        return @{
            Name             = $ModuleName
            Installed        = $false
            Version          = $null
            MeetsRequirement = $false
            RequiredVersion  = $RequiredVersion
        }
    }
}

# Install or update a module
function Install-RequiredModule {
    param(
        [string]$ModuleName,
        [version]$MinVersion,
        [string]$InstallScope,
        [bool]$ForceInstall
    )

    try {
        $status = Get-ModuleStatus -ModuleName $ModuleName -RequiredVersion $MinVersion

        if ($status.Installed -and $status.MeetsRequirement -and -not $ForceInstall) {
            Write-Status "$ModuleName $($status.Version) already installed (meets requirement)" -Type Success
            return $true
        }

        if ($status.Installed -and -not $status.MeetsRequirement) {
            Write-Status "$ModuleName $($status.Version) found but outdated (need $MinVersion+)" -Type Warning
            if (-not $CheckOnly) {
                Write-Host "  → Updating to latest version..." -ForegroundColor Yellow
                Update-Module -Name $ModuleName -Scope $InstallScope -Force -ErrorAction Stop
                $newVersion = (Get-Module -Name $ModuleName -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
                Write-Status "$ModuleName updated to $newVersion" -Type Success
            }
            return $true
        }

        if (-not $status.Installed -or $ForceInstall) {
            if ($ForceInstall -and $status.Installed) {
                Write-Status "$ModuleName $($status.Version) found, forcing reinstall..." -Type Warning
            }
            else {
                Write-Status "$ModuleName not found" -Type Warning
            }

            if (-not $CheckOnly) {
                Write-Host "  → Installing from PowerShell Gallery..." -ForegroundColor Cyan
                Install-Module -Name $ModuleName -Scope $InstallScope -Force -AllowClobber -Repository PSGallery -ErrorAction Stop
                $newVersion = (Get-Module -Name $ModuleName -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
                Write-Status "$ModuleName $newVersion installed successfully" -Type Success
            }
            return $true
        }
    }
    catch {
        Write-Status "Failed to install $ModuleName : $($_.Exception.Message)" -Type Error
        return $false
    }
}

# Main execution
try {
    Write-SectionHeader "Migration.Toolkit.Cloud - Prerequisites Installation"

    # Validate admin rights if AllUsers scope
    if ($Scope -eq 'AllUsers' -and -not (Test-IsAdmin)) {
        throw "AllUsers scope requires Administrator privileges. Run PowerShell as Administrator or use -Scope CurrentUser"
    }

    if ($CheckOnly) {
        Write-Status "CHECK ONLY mode - no installations will be performed" -Type Info
    }
    else {
        Write-Status "Installation scope: $Scope" -Type Info
        if ($Force) {
            Write-Status "Force mode enabled - will reinstall existing modules" -Type Warning
        }
    }

    # Check PSGallery is registered and trusted
    Write-Host "`nChecking PowerShell Gallery registration..."
    $gallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if (-not $gallery) {
        throw "PowerShell Gallery not registered. Run: Register-PSRepository -Default"
    }

    if ($gallery.InstallationPolicy -ne 'Trusted' -and -not $CheckOnly) {
        Write-Status "Setting PSGallery as trusted repository..." -Type Info
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    Write-Status "PowerShell Gallery ready" -Type Success

    # Track results
    $results = @{
        Graph    = @()
        Exchange = $null
        Failed   = @()
    }

    # Install Microsoft Graph SDK modules
    Write-SectionHeader "Microsoft Graph SDK Modules ($($graphModules.Count) modules)"
    Write-Status "Minimum version required: $MinimumVersion" -Type Info

    foreach ($module in $graphModules) {
        $success = Install-RequiredModule -ModuleName $module -MinVersion $MinimumVersion -InstallScope $Scope -ForceInstall $Force
        if ($success) {
            $results.Graph += $module
        }
        else {
            $results.Failed += $module
        }
    }

    # Install Exchange Online Management (unless skipped)
    if (-not $SkipExchange) {
        Write-SectionHeader "Exchange Online Management Module"
        Write-Status "Minimum version required: $exchangeMinVersion" -Type Info

        $success = Install-RequiredModule -ModuleName $exchangeModule -MinVersion $exchangeMinVersion -InstallScope $Scope -ForceInstall $Force
        if ($success) {
            $results.Exchange = $exchangeModule
        }
        else {
            $results.Failed += $exchangeModule
        }
    }
    else {
        Write-Status "Exchange Online module skipped (-SkipExchange specified)" -Type Warning
    }

    # Summary report
    Write-SectionHeader "Installation Summary"

    if ($CheckOnly) {
        Write-Status "Check complete (no installations performed)" -Type Info
    }

    Write-Host "Microsoft Graph SDK modules: $($results.Graph.Count)/$($graphModules.Count)" -ForegroundColor $(if ($results.Graph.Count -eq $graphModules.Count) { 'Green' } else { 'Yellow' })

    if (-not $SkipExchange) {
        Write-Host "Exchange Online module: $(if ($results.Exchange) { '✓' } else { '✗' })" -ForegroundColor $(if ($results.Exchange) { 'Green' } else { 'Red' })
    }

    if ($results.Failed.Count -gt 0) {
        Write-Host "`nFailed modules:" -ForegroundColor Red
        $results.Failed | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
        throw "Some modules failed to install. See errors above."
    }

    # Verification
    if (-not $CheckOnly) {
        Write-SectionHeader "Verification"
        Write-Host "Verifying module availability...`n"

        $verified = @()
        $failed = @()

        foreach ($module in $graphModules) {
            $available = Get-Module -Name $module -ListAvailable -ErrorAction SilentlyContinue
            if ($available) {
                $version = ($available | Sort-Object Version -Descending | Select-Object -First 1).Version
                Write-Host "  ✓ $module ($version)" -ForegroundColor Green
                $verified += $module
            }
            else {
                Write-Host "  ✗ $module (not found)" -ForegroundColor Red
                $failed += $module
            }
        }

        if (-not $SkipExchange) {
            $exAvailable = Get-Module -Name $exchangeModule -ListAvailable -ErrorAction SilentlyContinue
            if ($exAvailable) {
                $version = ($exAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version
                Write-Host "  ✓ $exchangeModule ($version)" -ForegroundColor Green
                $verified += $exchangeModule
            }
            else {
                Write-Host "  ✗ $exchangeModule (not found)" -ForegroundColor Red
                $failed += $exchangeModule
            }
        }

        Write-Host "`nVerification complete: $($verified.Count) available, $($failed.Count) missing" -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Red' })

        if ($failed.Count -gt 0) {
            throw "Module verification failed. Some modules are not available."
        }
    }

    # Final success message
    Write-SectionHeader "Prerequisites Ready"
    Write-Status "All required modules are installed and ready for cloud discovery!" -Type Success
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Import the Migration.Toolkit.Cloud module:" -ForegroundColor White
    Write-Host "     Import-Module Migration.Toolkit.Cloud" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Connect to your tenant:" -ForegroundColor White
    Write-Host "     Connect-AzCloudTenant -TenantId 'your-tenant.onmicrosoft.com' -ClientId 'your-app-id' ..." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Run discovery:" -ForegroundColor White
    Write-Host "     Invoke-AzCloudDiscovery -OutputRoot 'C:\Reports\CloudDiscovery' -Workloads All" -ForegroundColor Gray
    Write-Host ""

    exit 0
}
catch {
    Write-Host "`n" -NoNewline
    Write-Status "Installation failed: $($_.Exception.Message)" -Type Error
    Write-Host ""
    exit 1
}
