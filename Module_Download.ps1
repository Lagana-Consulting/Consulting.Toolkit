#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EngagementRoot = "C:\Scripts"
$Org = 'Lagana-Consulting'
$Repo = 'lc-toolkit'
$Ref = 'main'   # branch name OR tag OR commit SHA

# --- PS 5.1: ensure TLS 1.2 for GitHub ---
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # ignore; some locked-down environments restrict this
}

# Prompt for token securely (fine-grained PAT with Contents: Read)
$secureToken = Read-Host "Enter GitHub token (fine-grained PAT, Contents: Read)" -AsSecureString
$token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
)

if ([string]::IsNullOrWhiteSpace($token)) {
    throw "No token entered."
}

$headers = @{
    Authorization = "token $token"
    "User-Agent"  = "PowerShell-5.1"
    Accept        = "application/vnd.github+json"
}

# Use GitHub API zipball (reliable for private repos)
$zipUrl = "https://api.github.com/repos/$Org/$Repo/zipball/$Ref"

# Use short paths to avoid Windows 260-char MAX_PATH limit
$tempBase = "c:\temp"
$zip = Join-Path $tempBase "dl.zip"
$extractRoot = Join-Path $tempBase "ex"

# Ensure temp folder exists
if (-not (Test-Path -LiteralPath $tempBase)) {
    New-Item -ItemType Directory -Path $tempBase -Force | Out-Null
}

# Clean up any previous extraction
if (Test-Path -LiteralPath $extractRoot) {
    try {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        # Ignore cleanup errors
    }
}

Write-Host "Downloading $Org/$Repo ($Ref)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zip

if (-not (Test-Path -LiteralPath $zip)) {
    throw "Download failed: ZIP not found at $zip"
}

# Create extract folder
New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

Write-Host "Extracting..." -ForegroundColor Cyan
try {
    # Use .NET compression for more reliable extraction
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $extractRoot)
} catch {
    throw "Extraction failed: $($_.Exception.Message)"
}

# Wait briefly for file system to settle (handles antivirus/file locking delays)
Start-Sleep -Milliseconds 500

# Zipball extracts to a single random top folder; find it with retry
$maxRetries = 3
$attempt = 0
$top = $null

while ($attempt -lt $maxRetries -and -not $top) {
    $attempt++
    try {
        $top = Get-ChildItem -Path $extractRoot -Directory -ErrorAction Stop | Select-Object -First 1
        if (-not $top) {
            if ($attempt -lt $maxRetries) {
                Write-Host "  Retry $attempt/${maxRetries}: Extracted folder not yet visible, waiting..." -ForegroundColor Yellow
                Start-Sleep -Milliseconds 500
            }
        }
    } catch {
        if ($attempt -lt $maxRetries) {
            Write-Host "  Retry $attempt/${maxRetries}: $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Milliseconds 500
        } else {
            throw "Failed to enumerate extracted folder after ${maxRetries} attempts: $($_.Exception.Message)"
        }
    }
}

if (-not $top) {
    throw "Extraction failed: no folder found under $extractRoot after ${maxRetries} retries"
}

# Module path inside repo
$srcModule = Join-Path $top.FullName 'src\Lagana.Consulting.Toolkit'
if (-not (Test-Path -LiteralPath $srcModule)) {
    # Help diagnose if the folder moved
    $candidates = @()
    try {
        $candidates = Get-ChildItem -Path $top.FullName -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Lagana.Consulting.Toolkit' } |
        Select-Object -First 5 -ExpandProperty FullName
    } catch {
        # Ignore errors during recursive search (race conditions with antivirus/file system)
    }

    $hint = if ($candidates) { "`nFound candidates:`n - " + ($candidates -join "`n - ") } else { "" }
    throw "Module folder not found at expected path: $srcModule.$hint"
}

# Destination (project-local module)
$dstModule = Join-Path $EngagementRoot 'modules\Lagana.Consulting.Toolkit'
New-Item -ItemType Directory -Path (Split-Path $dstModule -Parent) -Force | Out-Null

Write-Host "Copying module to $dstModule ..." -ForegroundColor Cyan
Copy-Item -Path $srcModule -Destination $dstModule -Recurse -Force

Write-Host "Done." -ForegroundColor Green
Write-Host "Module path: $dstModule"
Write-Host "Import with: Import-Module `"$dstModule\Lagana.Consulting.Toolkit.psd1`" -Force"

# Cleanup temporary files
Write-Host "Cleaning up temporary files..." -ForegroundColor Cyan
try {
    if (Test-Path -LiteralPath $zip) {
        Remove-Item -LiteralPath $zip -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction Stop
    }
    Write-Host "Cleanup complete." -ForegroundColor Green
} catch {
    Write-Host "Warning: Could not fully clean temporary files: $($_.Exception.Message)" -ForegroundColor Yellow
}
