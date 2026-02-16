#Requires -Version 7.2
Set-StrictMode -Version Latest

$script:ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-DotSource {
    param(
        [Parameter(Mandatory)][string]$Path
    )
    try {
        . $Path
    } catch {
        throw "Failed dot-sourcing '$Path' in module '$($MyInvocation.MyCommand.ModuleName)'. Error: $($_.Exception.Message)"
    }
}

# --- Load Private first (helpers/classes), then Public (exported functions) ---
$privateDir = Join-Path $script:ModuleRoot 'Private'
$publicDir = Join-Path $script:ModuleRoot 'Public'

if (Test-Path -LiteralPath $privateDir) {
    Get-ChildItem -LiteralPath $privateDir -Filter '*.ps1' -File |
    Sort-Object FullName |
    ForEach-Object { Invoke-DotSource $_.FullName }
}

if (Test-Path -LiteralPath $publicDir) {
    Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -File |
    Sort-Object FullName |
    ForEach-Object { Invoke-DotSource $_.FullName }
}

# --- Optional: module initialization hook ---
$init = Join-Path $script:ModuleRoot 'Private\_Init.ps1'
if (Test-Path -LiteralPath $init) { Invoke-DotSource $init }

# --- Export ONLY public functions ---
# This assumes each Public\*.ps1 defines one or more functions.
$publicFunctions = @()
if (Test-Path -LiteralPath $publicDir) {
    $publicFunctions = Get-ChildItem -LiteralPath $publicDir -Filter '*.ps1' -File |
    ForEach-Object { $_.BaseName }
}

# If your public function names do NOT match filenames, use this instead:
# $publicFunctions = (Get-Command -Module $MyInvocation.MyCommand.Module -CommandType Function).Name

Export-ModuleMember -Function $publicFunctions -Alias @()
