param(
    [string]$DiscoveryPath
)

if (-not $DiscoveryPath) {
    $DiscoveryPath = Get-ChildItem "c:\scripts\Reports" -Directory -Filter "ADOnly*" -ErrorAction SilentlyContinue |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}

if (-not $DiscoveryPath) {
    Write-Error "No discovery folder found"
    exit 1
}

Write-Host "=== Discovery Output Structure ===" -ForegroundColor Cyan
Write-Host "Path: $DiscoveryPath`n"

# Root level CSVs
Write-Host "Root-level CSV files:" -ForegroundColor Yellow
Get-ChildItem $DiscoveryPath -Filter "*.csv" -File | Select-Object -ExpandProperty Name | Sort-Object

# Domain subdirectories
Write-Host "`nDomain subdirectories:" -ForegroundColor Yellow
$domainDirs = Get-ChildItem $DiscoveryPath -Directory | Where-Object { $_.Name -match "^Domain-" }
foreach ($ddir in $domainDirs) {
    Write-Host "`n  $($ddir.Name):" -ForegroundColor Cyan
    $csvs = Get-ChildItem $ddir.FullName -Filter "*.csv" -File
    if ($csvs) {
        $csvs | Select-Object -ExpandProperty Name | Sort-Object | ForEach-Object { Write-Host "    - $_" }
    } else {
        Write-Host "    (no CSV files found)"
    }
}
