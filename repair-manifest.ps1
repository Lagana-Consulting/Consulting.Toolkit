[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter()] [string] $RepoRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
      New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
  }
}

function New-ArchiveRoot([string]$Root) {
  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $a = Join-Path $Root "_archive\$stamp"
  Ensure-Dir $a
  return $a
}

function Move-ToArchive([string]$Path, [string]$ArchiveRoot) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $leaf = Split-Path -Leaf $Path
  $dest = Join-Path $ArchiveRoot $leaf
  if (Test-Path -LiteralPath $dest) {
    $dest = Join-Path $ArchiveRoot ("{0}_{1}" -f $leaf, (Get-Date).ToString("HHmmssfff"))
  }
  if ($PSCmdlet.ShouldProcess("$Path -> $dest", "Archive")) {
    Move-Item -LiteralPath $Path -Destination $dest -Force
  }
}

function Replace-InFile([string]$Path, [string]$Old, [string]$New) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $txt = Get-Content -LiteralPath $Path -Raw
  if ($txt -notmatch [regex]::Escape($Old)) { return }
  if ($PSCmdlet.ShouldProcess($Path, "Replace '$Old' -> '$New'")) {
    $txt2 = $txt -replace [regex]::Escape($Old), $New
    Set-Content -LiteralPath $Path -Value $txt2 -Encoding UTF8
  }
}

function Set-RequiredModules([string]$ManifestPath, [string[]]$ModuleNames) {
  if (-not (Test-Path -LiteralPath $ManifestPath)) { return }

  # Import the hashtable safely
  $data = Import-PowerShellDataFile -LiteralPath $ManifestPath

  # Build RequiredModules entries (loose: name only). Version pinning can come later.
  $req = @()
  foreach ($m in $ModuleNames) { $req += $m }

  $data['RequiredModules'] = $req

  if ($PSCmdlet.ShouldProcess($ManifestPath, "Update RequiredModules")) {
    # Preserve a readable psd1 format
    $out = "@`n@{`n"
    foreach ($k in $data.Keys) {
      $v = $data[$k]
      $out += "  $k = "
      switch ($v.GetType().Name) {
        'String' { $out += "'$v'`n" }
        'Object[]' {
          $out += "@(`n"
          foreach ($i in $v) { $out += "    '$i'`n" }
          $out += "  )`n"
        }
        default {
          # fallback to PowerShell formatting
          $out += ($v | Out-String).TrimEnd() + "`n"
        }
      }
    }
    $out += "}`n"
    Set-Content -LiteralPath $ManifestPath -Value $out -Encoding UTF8
  }
}

# -------------------------------------------------
# Paths
# -------------------------------------------------
$archiveRoot = New-ArchiveRoot $RepoRoot

$cloudDir = Join-Path $RepoRoot "src\Cloud.Toolkit.Discovery"
$cloudOld = Join-Path $cloudDir "Migration.Toolkit.Cloud.psd1"
$cloudNew = Join-Path $cloudDir "Cloud.Toolkit.Discovery.psd1"

$secDir = Join-Path $RepoRoot "src\Identity.Security.Assessment.Toolkit"
$secMain = Join-Path $secDir "Identity.Security.Assessment.Toolkit.psd1"
$secPublicManifest = Join-Path $secDir "Public\Identity.Security.Assessment.Toolkit.psd1"

$discDir = Join-Path $RepoRoot "src\Consulting.Toolkit.Discovery"
$discManifest = Join-Path $discDir "Consulting.Toolkit.Discovery.psd1"

$migAnalysis = Join-Path $RepoRoot "src\Migration.Toolkit.Analysis\Migration.Toolkit.Analysis.psd1"
$migAssess   = Join-Path $RepoRoot "src\Migration.Toolkit.Assessment\Migration.Toolkit.Assessment.psd1"

# -------------------------------------------------
# 1) Fix Cloud manifest file name + internal references
# -------------------------------------------------
if (Test-Path -LiteralPath $cloudOld) {
  if ($PSCmdlet.ShouldProcess("$cloudOld -> $cloudNew", "Rename Cloud manifest")) {
    Rename-Item -LiteralPath $cloudOld -NewName (Split-Path -Leaf $cloudNew) -Force
  }
}

# If the module still uses Migration.Toolkit.Cloud root module naming, normalize it
Replace-InFile -Path $cloudNew -Old "Migration.Toolkit.Cloud.psm1" -New "Cloud.Toolkit.Discovery.psm1"
Replace-InFile -Path $cloudNew -Old "Migration.Toolkit.Cloud"     -New "Cloud.Toolkit.Discovery"

# Also rename psm1 if present
$cloudPsm1Old = Join-Path $cloudDir "Migration.Toolkit.Cloud.psm1"
$cloudPsm1New = Join-Path $cloudDir "Cloud.Toolkit.Discovery.psm1"
if (Test-Path -LiteralPath $cloudPsm1Old) {
  if ($PSCmdlet.ShouldProcess("$cloudPsm1Old -> $cloudPsm1New", "Rename Cloud root module")) {
    Rename-Item -LiteralPath $cloudPsm1Old -NewName (Split-Path -Leaf $cloudPsm1New) -Force
  }
}

# -------------------------------------------------
# 2) Archive accidental "Public\*.psd1" (almost never a module manifest)
# -------------------------------------------------
if (Test-Path -LiteralPath $secPublicManifest) {
  Move-ToArchive -Path $secPublicManifest -ArchiveRoot $archiveRoot
}

# -------------------------------------------------
# 3) Set dependencies (RequiredModules) to match your diagram
#    (using name-only; version pinning later)
# -------------------------------------------------

# Discovery: depends on nothing else (for now, since Core/Logging/Output not present in your list)
# If you later add Core/Logging/Output manifests, update these to include them.
Set-RequiredModules -ManifestPath $discManifest -ModuleNames @()

# Cloud Discovery: depends on Discovery (optional) — or empty if it’s standalone
# I recommend empty unless cloud discovery directly imports discovery helpers.
Set-RequiredModules -ManifestPath $cloudNew -ModuleNames @()

# Migration.Analysis: depends on Consulting.Toolkit.Discovery (it should consume outputs, but this is fine)
Set-RequiredModules -ManifestPath $migAnalysis -ModuleNames @("Consulting.Toolkit.Discovery")

# Migration.Assessment: depends on Migration.Analysis
Set-RequiredModules -ManifestPath $migAssess -ModuleNames @("Migration.Toolkit.Analysis")

# Security toolkit: depends on Migration.Analysis OR Consulting.Toolkit.Discovery.
# Better is Analysis, but since you only have Migration.Toolkit.Analysis right now:
Set-RequiredModules -ManifestPath $secMain -ModuleNames @("Migration.Toolkit.Analysis")

# -------------------------------------------------
# 4) Validate manifests
# -------------------------------------------------
Write-Host ""
Write-Host "Manifest validation (Test-ModuleManifest):"
$manifests = @($discManifest, $cloudNew, $secMain, $migAnalysis, $migAssess) | Where-Object { Test-Path -LiteralPath $_ }
foreach ($m in $manifests) {
  try {
    Test-ModuleManifest -Path $m | Out-Null
    Write-Host "  OK  $m"
  } catch {
    Write-Host "  BAD $m"
    Write-Host "      $($_.Exception.Message)"
  }
}

Write-Host ""
Write-Host "Archived items (if any) to: $archiveRoot"
Write-Host "Done."
