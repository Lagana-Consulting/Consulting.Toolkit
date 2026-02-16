function Get-SATOutputRoot {
    [CmdletBinding()]
    param ()

    return (Get-SATOutputRootInternal)
}
