# --- Paths
$analysisDir = Resolve-Path ".\src\Migration.Toolkit.Analysis"
$assessDir = Resolve-Path ".\src\Migration.Toolkit.Assessment"

$analysisPsd1 = Join-Path $analysisDir "Migration.Toolkit.Analysis.psd1"
$assessPsd1 = Join-Path $assessDir  "Migration.Toolkit.Assessment.psd1"

# --- Archive current empty files (if present)
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$archive = ".\_archive\$stamp\empty-manifests"
New-Item -ItemType Directory -Force $archive | Out-Null

foreach ($p in @($analysisPsd1, $assessPsd1)) {
    if (Test-Path $p) { Copy-Item $p (Join-Path $archive (Split-Path $p -Leaf)) -Force }
}

# --- Determine root modules (.psm1)
$analysisRoot = Join-Path $analysisDir "Migration.Toolkit.Analysis.psm1"
$assessRoot = Join-Path $assessDir  "Migration.Toolkit.Assessment.psm1"

if (-not (Test-Path $analysisRoot)) {
    $analysisRoot = (Get-ChildItem $analysisDir -Filter *.psm1 -File | Select-Object -First 1).FullName
}
if (-not (Test-Path $assessRoot)) {
    $assessRoot = (Get-ChildItem $assessDir -Filter *.psm1 -File | Select-Object -First 1).FullName
}

if (-not $analysisRoot) { throw "No .psm1 found in $analysisDir. Create a root module file first." }
if (-not $assessRoot) { throw "No .psm1 found in $assessDir. Create a root module file first." }

# --- Create manifests
New-ModuleManifest `
    -Path $analysisPsd1 `
    -RootModule (Split-Path $analysisRoot -Leaf) `
    -ModuleVersion "0.1.0" `
    -Author "Lagana Consulting" `
    -CompanyName "Lagana Consulting" `
    -Copyright "(c) $(Get-Date -Format yyyy) Lagana Consulting" `
    -Description "Migration analysis module (migration-focused interpretation of discovery outputs)." `
    -PowerShellVersion "7.2" `
    -CompatiblePSEditions @('Core') `
    -FunctionsToExport @('*') `
    -CmdletsToExport @() `
    -AliasesToExport @() `
    -VariablesToExport @() `
    -RequiredModules @()

New-ModuleManifest `
    -Path $assessPsd1 `
    -RootModule (Split-Path $assessRoot -Leaf) `
    -ModuleVersion "0.1.0" `
    -Author "Lagana Consulting" `
    -CompanyName "Lagana Consulting" `
    -Copyright "(c) $(Get-Date -Format yyyy) Lagana Consulting" `
    -Description "Migration assessment module (readiness checks, conflicts, and assessment reporting)." `
    -PowerShellVersion "7.2" `
    -CompatiblePSEditions @('Core') `
    -FunctionsToExport @('*') `
    -CmdletsToExport @() `
    -AliasesToExport @() `
    -VariablesToExport @() `
    -RequiredModules @()

# --- Validate
Test-ModuleManifest $analysisPsd1 | Format-Table Name, Version, ModuleType
Test-ModuleManifest $assessPsd1   | Format-Table Name, Version, ModuleType
