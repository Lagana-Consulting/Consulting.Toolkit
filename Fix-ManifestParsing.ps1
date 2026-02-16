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
  $a = Join-Path $Root "_archive\$stamp"
  Ensure-Dir $a
  return $a
}

function Is-DividerLine([string]$line) {
  # matches "----", "----   -----", "----- ----- -----"
  return ($line -match '^\s*-{2,}\s*(\s*-{2,}\s*)*$')
}

$archive = New-ArchiveRoot $RepoRoot
$manifests = Get-ChildItem -LiteralPath (Join-Path $RepoRoot "src") -Recurse -Filter *.psd1 |
Where-Object { $_.Name -notlike '*PSScriptAnalyzerSettings*' }

foreach ($m in $manifests) {
  $path = $m.FullName
  Write-Host "`n==> Fixing: $path"

  $backup = Join-Path $archive ($m.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '[:\\\/]', '_')
  Ensure-Dir (Split-Path -Parent $backup)

  if ($PSCmdlet.ShouldProcess($path, "Backup to $backup")) {
    Copy-Item -LiteralPath $path -Destination $backup -Force
  }

  $lines = Get-Content -LiteralPath $path -ErrorAction Stop

  # Remove divider lines
  $lines = $lines | Where-Object { -not (Is-DividerLine $_) }

  # Trim leading empty lines
  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
    $lines = $lines[1..($lines.Count - 1)]
  }

  # Fix first token: if first line is just "@", change to "@{"
  if ($lines.Count -gt 0 -and $lines[0].Trim() -eq "@") {
    $lines[0] = "@{"
  }

  # If it doesn't start with "@{", try to coerce by prepending "@{" if it starts with "{"
  if ($lines.Count -gt 0 -and $lines[0].Trim() -ne "@{") {
    if ($lines[0].Trim().StartsWith("{")) {
      $lines[0] = "@{"
    }
  }

  # Ensure ends with "}" (very light guardrail)
  $lastNonEmptyIdx = ($lines.Count - 1)
  while ($lastNonEmptyIdx -ge 0 -and [string]::IsNullOrWhiteSpace($lines[$lastNonEmptyIdx])) {
    $lastNonEmptyIdx--
  }
  if ($lastNonEmptyIdx -ge 0 -and $lines[$lastNonEmptyIdx].Trim() -ne "}") {
    $lines += "}"
  }

  if ($PSCmdlet.ShouldProcess($path, "Write repaired manifest")) {
    Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
  }

  # Validate parseability (module manifest)
  try {
    Test-ModuleManifest -Path $path | Out-Null
    Write-Host "   OK: Test-ModuleManifest passed"
  } catch {
    Write-Host "   STILL BAD: $($_.Exception.Message)"
  }
}

Write-Host "`nBackups stored in: $archive"
Write-Host "Done."
