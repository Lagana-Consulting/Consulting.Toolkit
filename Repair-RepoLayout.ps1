[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter()] [string] $RepoRoot = (Get-Location).Path,
  [switch] $NoArchive,
  [switch] $SkipGitIgnoreUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-ArchiveRoot {
  param([string]$Root, [switch]$NoArchive)
  if ($NoArchive) { return $null }
  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $a = Join-Path $Root "_archive\$stamp"
  if ($PSCmdlet.ShouldProcess($a, "Create archive root")) {
    New-Item -ItemType Directory -Force -Path $a | Out-Null
  }
  return $a
}

function Ensure-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
      New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
  }
}

function Get-FileTimeUtc {
  param([string]$Path)
  try { return (Get-Item -LiteralPath $Path).LastWriteTimeUtc }
  catch { return [datetime]::MinValue }
}

function Copy-NewerFile {
  param(
    [Parameter(Mandatory)] [string] $SourceFile,
    [Parameter(Mandatory)] [string] $DestFile
  )

  $srcTime = Get-FileTimeUtc $SourceFile
  $dstTime = if (Test-Path -LiteralPath $DestFile) { Get-FileTimeUtc $DestFile } else { [datetime]::MinValue }

  # Latest timestamp wins (source overwrites dest only if newer)
  if ($srcTime -gt $dstTime) {
    Ensure-Dir (Split-Path -Parent $DestFile)
    if ($PSCmdlet.ShouldProcess("$DestFile", "Overwrite with newer from $SourceFile ($srcTime > $dstTime)")) {
      Copy-Item -LiteralPath $SourceFile -Destination $DestFile -Force
    }
  } elseif (-not (Test-Path -LiteralPath $DestFile)) {
    Ensure-Dir (Split-Path -Parent $DestFile)
    if ($PSCmdlet.ShouldProcess("$DestFile", "Copy from $SourceFile (dest missing)")) {
      Copy-Item -LiteralPath $SourceFile -Destination $DestFile -Force
    }
  }
}

function Merge-FolderLatestWins {
  param(
    [Parameter(Mandatory)] [string] $SourceDir,
    [Parameter(Mandatory)] [string] $DestDir,
    [hashtable] $FileRenameMap = @{}
  )
  if (-not (Test-Path -LiteralPath $SourceDir)) { return }

  Ensure-Dir $DestDir

  $srcRoot = (Resolve-Path -LiteralPath $SourceDir).Path
  $dstRoot = (Resolve-Path -LiteralPath $DestDir).Path

  Get-ChildItem -LiteralPath $srcRoot -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($srcRoot.Length).TrimStart('\','/')
    $destRel = if ($FileRenameMap.ContainsKey($rel)) { $FileRenameMap[$rel] } else { $rel }
    $destFile = Join-Path $dstRoot $destRel
    Copy-NewerFile -SourceFile $_.FullName -DestFile $destFile
  }
}

function Move-ToArchive {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [string] $ArchiveRoot
  )
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $leaf = Split-Path -Leaf $Path
  $dest = Join-Path $ArchiveRoot $leaf

  # Avoid collisions in archive
  if (Test-Path -LiteralPath $dest) {
    $dest = Join-Path $ArchiveRoot ("{0}_{1}" -f $leaf, (Get-Date).ToString("HHmmssfff"))
  }

  if ($PSCmdlet.ShouldProcess("$Path -> $dest", "Archive")) {
    Ensure-Dir (Split-Path -Parent $dest)
    Move-Item -LiteralPath $Path -Destination $dest -Force
  }
}

function Ensure-GitIgnore {
  param([string]$GitIgnorePath)

  $linesToEnsure = @(
    ".vs/",
    "**/.vs/",
    "**/bin/",
    "**/obj/",
    "_work/",
    "output/",
    "logs/",
    "dist/",
    "compare/",
    "*.zip",
    "*.7z"
  )

  $existing = if (Test-Path -LiteralPath $GitIgnorePath) {
    Get-Content -LiteralPath $GitIgnorePath -ErrorAction SilentlyContinue
  } else { @() }

  $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $existing | ForEach-Object { [void]$set.Add($_.Trim()) }

  foreach ($l in $linesToEnsure) {
    if (-not $set.Contains($l)) {
      if ($PSCmdlet.ShouldProcess($GitIgnorePath, "Add ignore '$l'")) {
        Add-Content -LiteralPath $GitIgnorePath -Value $l
        [void]$set.Add($l)
      }
    }
  }
}

# ----------------------------
# Start
# ----------------------------
$archiveRoot = New-ArchiveRoot -Root $RepoRoot -NoArchive:$NoArchive

$src = Join-Path $RepoRoot "src"

# Canonical destinations
$destMigrationAnalysis   = Join-Path $src "Migration.Toolkit.Analysis"
$destMigrationAssessment = Join-Path $src "Migration.Toolkit.Assessment"
$destCloudDiscovery      = Join-Path $src "Cloud.Toolkit.Discovery"
$destSecurityToolkit     = Join-Path $src "Identity.Security.Assessment.Toolkit"

# Sources (common duplicates/misplacements)
$srcMisplacedAnalysis = Join-Path $src "Consulting.Toolkit.Analysis"              # contains Migration.Toolkit.Analysis files today
$srcLegacyMigAnalysis = Join-Path $RepoRoot "Migration.Toolkit\src\Migration.Toolkit.Analysis"
$srcLegacyMigAssess   = Join-Path $RepoRoot "Migration.Toolkit\src\Migration.Toolkit.Assessment"
$srcLegacyMigCloud    = Join-Path $RepoRoot "Migration.Toolkit\src\Migration.Toolkit.Cloud"
$srcLegacySec         = Join-Path $RepoRoot "Identity.Security.Assessment.Toolkit\src"
$srcEmptySecInSrc     = Join-Path $src "Identity.Security.Assessment.Toolkit\src" # often empty placeholder

# 1) Merge Analysis into src/Migration.Toolkit.Analysis (latest wins)
Merge-FolderLatestWins -SourceDir $srcMisplacedAnalysis -DestDir $destMigrationAnalysis
Merge-FolderLatestWins -SourceDir $srcLegacyMigAnalysis -DestDir $destMigrationAnalysis

# 2) Merge Assessment into src/Migration.Toolkit.Assessment
Merge-FolderLatestWins -SourceDir $srcLegacyMigAssess -DestDir $destMigrationAssessment

# 3) Merge Cloud module into src/Cloud.Toolkit.Discovery with key renames
#    (maps module entry files to the Cloud.Toolkit.Discovery naming)
$cloudRename = @{
  "Migration.Toolkit.Cloud.psm1" = "Cloud.Toolkit.Discovery.psm1"
  "Migration.Toolkit.Cloud.psd1" = "Cloud.Toolkit.Discovery.psd1"
}
Merge-FolderLatestWins -SourceDir $srcLegacyMigCloud -DestDir $destCloudDiscovery -FileRenameMap $cloudRename

# 4) Merge Security toolkit into src/Identity.Security.Assessment.Toolkit
Merge-FolderLatestWins -SourceDir $srcLegacySec -DestDir $destSecurityToolkit

# 5) Archive the “rest” (duplicates + generated artifacts)
if (-not $NoArchive) {
  # Archive top-level clutter
  foreach ($p in @("output","logs","dist","compare")) {
    $full = Join-Path $RepoRoot $p
    if (Test-Path -LiteralPath $full) { Move-ToArchive -Path $full -ArchiveRoot $archiveRoot }
  }

  # Archive old nested toolkit roots that are duplicative or non-canonical
  foreach ($p in @(
    "Migration.Toolkit",
    "Identity.Security.Assessment.Toolkit"
  )) {
    $full = Join-Path $RepoRoot $p
    if (Test-Path -LiteralPath $full) { Move-ToArchive -Path $full -ArchiveRoot $archiveRoot }
  }

  # Archive misplaced analysis folder after merge
  if (Test-Path -LiteralPath $srcMisplacedAnalysis) {
    Move-ToArchive -Path $srcMisplacedAnalysis -ArchiveRoot $archiveRoot
  }

  # Archive empty placeholder src under security (optional)
  if (Test-Path -LiteralPath $srcEmptySecInSrc) {
    # If it still exists and is empty, archive it to reduce confusion
    $files = Get-ChildItem -LiteralPath $srcEmptySecInSrc -Recurse -File -ErrorAction SilentlyContinue
    if (-not $files) {
      Move-ToArchive -Path $srcEmptySecInSrc -ArchiveRoot $archiveRoot
    }
  }
}

# 6) Update .gitignore to prevent re-growth of junk
if (-not $SkipGitIgnoreUpdate) {
  $gitignore = Join-Path $RepoRoot ".gitignore"
  Ensure-GitIgnore -GitIgnorePath $gitignore
}

Write-Host ""
Write-Host "Done."
if ($archiveRoot) { Write-Host "Archived leftovers to: $archiveRoot" }
Write-Host "Next: run 'git status' and validate your src/* modules import correctly."
