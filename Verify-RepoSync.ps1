<#
.SYNOPSIS
Verify local repo is in sync with remote (GitHub).

.DESCRIPTION
Checks git status, fetches remote, compares local HEAD vs origin/main SHAs, and reports pass/fail.

.EXAMPLE
.\Verify-RepoSync.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Repository Sync Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if we're in a git repo
try {
    $repoRoot = git rev-parse --show-toplevel 2>$null
    if (-not $repoRoot) { throw "Not a git repository" }
} catch {
    Write-Host "ERROR: Not a git repository" -ForegroundColor Red
    exit 1
}

Write-Host "[1/5] Checking local working tree..." -ForegroundColor Yellow
$status = git status --porcelain=v1
if ($status) {
    Write-Host "  WARNING: Uncommitted changes detected:" -ForegroundColor Yellow
    $status | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
} else {
    Write-Host "  OK: Working tree clean" -ForegroundColor Green
}
Write-Host ""

Write-Host "[2/5] Fetching from remote..." -ForegroundColor Yellow
try {
    $fetchResult = git fetch origin 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARNING: Fetch failed (check SSH key or network)" -ForegroundColor Yellow
        Write-Host "  Skipping remote comparison..." -ForegroundColor Gray
        $skipRemote = $true
    } else {
        Write-Host "  OK: Fetch complete" -ForegroundColor Green
        $skipRemote = $false
    }
} catch {
    Write-Host "  WARNING: Fetch failed: $_" -ForegroundColor Yellow
    $skipRemote = $true
}
Write-Host ""

Write-Host "[3/5] Comparing local vs remote..." -ForegroundColor Yellow
if (-not $skipRemote) {
    $localSha = git rev-parse HEAD
    $remoteSha = git rev-parse origin/main

    Write-Host "  Local HEAD:  $localSha" -ForegroundColor White
    Write-Host "  Remote main: $remoteSha" -ForegroundColor White

    if ($localSha -eq $remoteSha) {
        Write-Host "  OK: Local and remote are in sync" -ForegroundColor Green
        $inSync = $true
    } else {
        Write-Host "  ERROR: Local and remote differ" -ForegroundColor Red
        $inSync = $false
    }
} else {
    Write-Host "  SKIPPED: Remote fetch unavailable" -ForegroundColor Gray
    $inSync = $null
}
Write-Host ""

Write-Host "[4/5] Checking branch status..." -ForegroundColor Yellow
if (-not $skipRemote) {
    $branch = git rev-parse --abbrev-ref HEAD
    $upstream = git rev-parse --abbrev-ref '@{u}' 2>$null
    if ($upstream) {
        $aheadBehind = git rev-list --left-right --count HEAD...origin/main
        $ahead = ($aheadBehind -split '\s+')[0]
        $behind = ($aheadBehind -split '\s+')[1]

        Write-Host "  Branch: $branch -> $upstream" -ForegroundColor White
        Write-Host "  Ahead: $ahead | Behind: $behind" -ForegroundColor White

        if ($ahead -eq 0 -and $behind -eq 0) {
            Write-Host "  OK: Branch up to date" -ForegroundColor Green
        } elseif ($ahead -gt 0 -and $behind -eq 0) {
            Write-Host "  WARNING: Local ahead by $ahead commits (push needed)" -ForegroundColor Yellow
        } elseif ($behind -gt 0 -and $ahead -eq 0) {
            Write-Host "  WARNING: Local behind by $behind commits (pull needed)" -ForegroundColor Yellow
        } else {
            Write-Host "  WARNING: Diverged (ahead: $ahead, behind: $behind)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Branch: $branch (no upstream)" -ForegroundColor Gray
    }
} else {
    Write-Host "  SKIPPED: Remote fetch unavailable" -ForegroundColor Gray
}
Write-Host ""

Write-Host "[5/5] Recent commits..." -ForegroundColor Yellow
Write-Host "  Local:" -ForegroundColor White
git log --oneline -n 3 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
if (-not $skipRemote) {
    Write-Host "  Remote:" -ForegroundColor White
    git log origin/main --oneline -n 3 | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
}
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
if ($inSync -eq $true -and -not $status) {
    Write-Host "PASS: Repo is clean and in sync" -ForegroundColor Green
} elseif ($inSync -eq $true) {
    Write-Host "PARTIAL: In sync but uncommitted changes exist" -ForegroundColor Yellow
} elseif ($inSync -eq $false) {
    Write-Host "FAIL: Local and remote differ" -ForegroundColor Red
} else {
    Write-Host "PARTIAL: Local status OK, remote unavailable" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
