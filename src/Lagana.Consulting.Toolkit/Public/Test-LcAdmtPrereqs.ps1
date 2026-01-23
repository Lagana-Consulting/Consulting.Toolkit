function Test-LcAdmtPrereqs {
    [CmdletBinding()]
    param(
        [string]$AdmtExecutablePath,

        [string[]]$AdditionalSearchPaths,

        [switch]$SkipAdmtExecutableCheck,

        [switch]$ThrowOnFailure
    )

    $messages = New-Object System.Collections.Generic.List[string]

    # PowerShell 5.1 (Desktop) only runs on Windows; PowerShell 6+ (Core) has $IsWindows variable
    $isWindows = if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $true
    } elseif (Test-Path variable:global:IsWindows) {
        $IsWindows
    } else {
        $true
    }
    if (-not $isWindows) { $messages.Add('ADMT requires Windows. This host is not Windows.') }

    $hasAdModule = [bool](Get-Command Get-ADForest -ErrorAction SilentlyContinue)
    if (-not $hasAdModule) { $messages.Add('ActiveDirectory module not available. Install RSAT AD DS tools.') }

    $candidates = @()
    if ($AdmtExecutablePath) { $candidates += $AdmtExecutablePath }
    if ($AdditionalSearchPaths) { $candidates += $AdditionalSearchPaths }
    if ($env:SystemRoot) { $candidates += (Join-Path $env:SystemRoot 'ADMT\ADMT.exe') }
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'ADMT\ADMT.exe') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'ADMT\ADMT.exe') }

    $admtExe = $null
    foreach ($candidate in $candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        $candidatePath = $candidate
        try { $candidatePath = Resolve-LcPath -Path $candidate } catch { $candidatePath = $candidate }

        if (Test-Path -LiteralPath $candidatePath) {
            $admtExe = (Get-Item -LiteralPath $candidatePath).FullName
            break
        }
    }

    if (-not $admtExe) {
        $admtCmd = Get-Command admt -ErrorAction SilentlyContinue
        if ($admtCmd -and $admtCmd.Path) { $admtExe = $admtCmd.Path }
    }

    $hasAdmtExe = [bool]$admtExe

    if (-not $hasAdmtExe) {
        if ($SkipAdmtExecutableCheck) {
            $messages.Add('ADMT executable not found; skipping per -SkipAdmtExecutableCheck.')
        } else {
            $messages.Add('ADMT executable not found. Install ADMT or pass -AdmtExecutablePath.')
        }
    }

    $passed = $isWindows -and $hasAdModule -and ($SkipAdmtExecutableCheck -or $hasAdmtExe)

    $result = [pscustomobject]@{
        IsWindows                = $isWindows
        HasActiveDirectoryModule = $hasAdModule
        AdmtExecutableFound      = $hasAdmtExe
        AdmtExecutablePath       = $admtExe
        CheckedExecutablePaths   = $candidates
        Messages                 = $messages.ToArray()
        Passed                   = $passed
    }

    if ($ThrowOnFailure -and -not $passed) {
        $detail = if ($messages.Count -gt 0) { $messages -join '; ' } else { 'Unknown failure' }
        throw "ADMT prerequisite check failed. $detail"
    }

    return $result
}
