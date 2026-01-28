[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot,
    [string]$SrcRoot = 'src',
    [string]$OutDir = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'

function Get-ModuleVersionFromManifest {
    param([Parameter(Mandatory)][string]$ManifestPath)

    if (-not (Test-Path $ManifestPath)) {
        throw "Manifest not found: $ManifestPath"
    }

    $data = Import-PowerShellDataFile -Path $ManifestPath
    $ver = [string]$data.ModuleVersion
    if ([string]::IsNullOrWhiteSpace($ver)) {
        throw "ModuleVersion missing in: $ManifestPath"
    }
    return $ver
}

function New-ReleaseZip {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$ModuleSourcePath,
        [Parameter(Mandatory)][string]$OutDir
    )

    $manifest = Join-Path $ModuleSourcePath "$ModuleName.psd1"
    $version = Get-ModuleVersionFromManifest -ManifestPath $manifest

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $stageRoot = Join-Path $OutDir "_stage_$ModuleName"
    if (Test-Path $stageRoot) { Remove-Item $stageRoot -Recurse -Force }

    $targetDir = Join-Path $stageRoot (Join-Path $ModuleName $version)
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    # Copy module content into version folder (exclude tests, temp files)
    Get-ChildItem -Path $ModuleSourcePath -Exclude '.git*', 'tests', '*.Tests.ps1' |
    Copy-Item -Destination $targetDir -Recurse -Force

    $zipName = "$ModuleName.$version.zip"
    $zipPath = Join-Path $OutDir $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    Compress-Archive -Path (Join-Path $stageRoot '*') -DestinationPath $zipPath -Force

    # Write checksum (optional but nice)
    $shaPath = "$zipPath.sha256"
    (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash | Out-File -FilePath $shaPath -Encoding ascii -Force

    Remove-Item $stageRoot -Recurse -Force

    [pscustomobject]@{
        ModuleName = $ModuleName
        Version    = $version
        ZipPath    = $zipPath
        Sha256Path = $shaPath
    }
}

# ---- Build both modules ----
$modules = @(
    'Migration.Toolkit',
    'Migration.Toolkit.Analysis'
)

$results = foreach ($m in $modules) {
    $srcPath = Join-Path $RepoRoot (Join-Path $SrcRoot $m)
    if (-not (Test-Path $srcPath)) {
        throw "Module folder not found: $srcPath"
    }
    New-ReleaseZip -ModuleName $m -ModuleSourcePath $srcPath -OutDir $OutDir
}

$results | ForEach-Object {
    Write-Host ("Built: {0} (v{1})" -f $_.ZipPath, $_.Version) -ForegroundColor Green
    Write-Host ("SHA  : {0}" -f $_.Sha256Path) -ForegroundColor Cyan
}

Write-Host "`nInstallation instructions:" -ForegroundColor Yellow
Write-Host "1. Extract ZIP to: `$env:ProgramFiles\WindowsPowerShell\Modules\" -ForegroundColor Gray
Write-Host "2. Import with: Import-Module <ModuleName>" -ForegroundColor Gray
