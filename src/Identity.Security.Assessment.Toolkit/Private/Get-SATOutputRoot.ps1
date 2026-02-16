function Get-SATOutputRoot {
    [CmdletBinding()]
    param ()

    if ($script:SATOutputRoot) {
        return $script:SATOutputRoot
    }

    if ($env:SAT_OUTPUT_ROOT) {
        return $env:SAT_OUTPUT_ROOT
    }

    return (Join-Path $env:USERPROFILE 'Documents\Identity.Security.Assessment.Toolkit\output')
}
