# Identity.Security.Assessment.Toolkit
# Module loader

# Load private helpers first
$moduleRoot = $PSScriptRoot
Get-ChildItem -Path (Join-Path $moduleRoot 'Private') -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
ForEach-Object {
    . $_.FullName
}

# Load internal modules
Get-ChildItem -Path (Join-Path $moduleRoot 'Modules') -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
ForEach-Object {
    . $_.FullName
}

# Load public entry points last
Get-ChildItem -Path (Join-Path $moduleRoot 'Public') -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
ForEach-Object {
    . $_.FullName
}
