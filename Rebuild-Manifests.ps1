[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$RepoRoot = (Get-Location).Path
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
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $a = Join-Path $Root "_archive\$stamp\manifests"
  Ensure-Dir $a
  return $a
}

function Backup-File([string]$Path, [string]$ArchiveRoot) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $nameLeaf = Split-Path -Leaf $Path
  $dest = Join-Path $ArchiveRoot $nameLeaf
  if (Test-Path -LiteralPath $dest) {
    $dest = Join-Path $ArchiveRoot ("{0}_{1}" -f $nameLeaf, (Get-Date).ToString("HHmmssfff"))
  }
  if ($PSCmdlet.ShouldProcess("$Path -> $dest", "Backup manifest")) {
    Copy-Item -LiteralPath $Path -Destination $dest -Force
  }
}

function Find-RootModule([string]$ModuleDir, [string]$PreferredName) {
  $preferred = Join-Path $ModuleDir ($PreferredName + ".psm1")
  if (Test-Path -LiteralPath $preferred) { return (Split-Path -Leaf $preferred) }

  $psm1 = Get-ChildItem -LiteralPath $ModuleDir -Filter *.psm1 -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($psm1) { return $psm1.Name }

  return $null
}

$archive = New-ArchiveRoot $RepoRoot

$modules = @(
  @{
    Name            = "Consulting.Toolkit.Discovery"
    Dir             = Join-Path $RepoRoot "src\Consulting.Toolkit.Discovery"
    Manifest        = Join-Path $RepoRoot "src\Consulting.Toolkit.Discovery\Consulting.Toolkit.Discovery.psd1"
    RequiredModules = @()
  },
  @{
    Name            = "Cloud.Toolkit.Discovery"
    Dir             = Join-Path $RepoRoot "src\Cloud.Toolkit.Discovery"
    Manifest        = Join-Path $RepoRoot "src\Cloud.Toolkit.Discovery\Cloud.Toolkit.Discovery.psd1"
    RequiredModules = @()
  },
  @{
    Name            = "Migration.Toolkit.Analysis"
    Dir             = Join-Path $RepoRoot "src\Migration.Toolkit.Analysis"
    Manifest        = Join-Path $RepoRoot "src\Migration.Toolkit.Analysis\Migration.Toolkit.Analysis.psd1"
    RequiredModules = @("Consulting.Toolkit.Discovery")
  },
  @{
    Name            = "Migration.Toolkit.Assessment"
    Dir             = Join-Path $RepoRoot "src\Migration.Toolkit.Assessment"
    Manifest        = Join-Path $RepoRoot "src\Migration.Toolkit.Assessment\Migration.Toolkit.Assessment.psd1"
    RequiredModules = @("Migration.Toolkit.Analysis")
  },
  @{
    Name            = "Identity.Security.Assessment.Toolkit"
    Dir             = Join-Path $RepoRoot "src\Identity.Security.Assessment.Toolkit"
    Manifest        = Join-Path $RepoRoot "src\Identity.Security.Assessment.Toolkit\Identity.Security.Assessment.Toolkit.psd1"
    RequiredModules = @("Consulting.Toolkit.Discovery")
  }
)

foreach ($m in $modules) {
  $dir = $m.Dir
  $modName = $m.Name
  $manifestPath = $m.Manifest

  if (-not (Test-Path -LiteralPath $dir)) {
    Write-Warning "Skipping $modName (folder missing): $dir"
    continue
  }

  Ensure-Dir $dir
  Backup-File -Path $manifestPath -ArchiveRoot $archive

  $rootModule = Find-RootModule -ModuleDir $dir -PreferredName $modName
  if (-not $rootModule) {
    Write-Warning "${modName}: No .psm1 found in $dir. Manifest will be created, but Import-Module will fail until a root .psm1 exists."
  }

  Write-Host "`n==> Rebuilding manifest for $modName"

  if ($PSCmdlet.ShouldProcess($manifestPath, "New-ModuleManifest")) {
    New-ModuleManifest `
      -Path $manifestPath `
      -RootModule $rootModule `
      -ModuleVersion "0.1.0" `
      -Author "Lagana Consulting" `
      -CompanyName "Lagana Consulting" `
      -Copyright "(c) $(Get-Date -Format yyyy) Lagana Consulting" `
      -Description "$modName module" `
      -PowerShellVersion "7.2" `
      -RequiredModules $m.RequiredModules `
      -FunctionsToExport @() `
      -CmdletsToExport @() `
      -AliasesToExport @() `
      -VariablesToExport @() `
      -FormatsToProcess @() `
      -TypesToProcess @()
  }

  try {
    Test-ModuleManifest -Path $manifestPath | Out-Null
    Write-Host "   OK: Test-ModuleManifest passed"
  } catch {
    Write-Host "   BAD: $($_.Exception.Message)"
  }
}

Write-Host "`nBackups stored in: $archive"
Write-Host "Done."
