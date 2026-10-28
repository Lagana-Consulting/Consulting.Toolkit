function Invoke-AdDiscoveryExport {
    <#
    .SYNOPSIS
    Executes a pure Active Directory discovery collection run.

    .DESCRIPTION
    Performs live AD data collection using Invoke-AdDiscovery and
    generates a Discovery Index file describing all collected datasets.

    This command:
      • Collects AD data (no analysis)
      • Writes structured CSV output
      • Generates Discovery.Index.json

    This command does NOT:
      • Perform risk scoring
      • Compare environments
      • Generate HTML reports
      • Run duplicate detection
      • Perform migration readiness logic

    .PARAMETER Environment
    Logical label (Source, Target, Production, etc.)

    .PARAMETER OutputRoot
    Root path where discovery run folder will be created.

    .PARAMETER CustomerName
    Optional metadata stored in discovery index.

    .PARAMETER Server
    Optional specific DC.

    .EXAMPLE
    Invoke-AdDiscoveryExport -Environment Source -OutputRoot C:\Discovery
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Environment = 'Source',

        [Parameter()]
        [string]$OutputRoot = 'C:\Discovery',

        [Parameter()]
        [string]$CustomerName,

        [Parameter()]
        [string]$Server,

        [string[]]$Domain,

        [switch]$IncludeSecurity
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Host "========================================"
    Write-Host "Consulting.Toolkit.Discovery Collector"
    Write-Host "========================================"
    Write-Host ""

    # Build parameter splat for Invoke-AdDiscovery
    $invokeParams = @{
        Environment  = $Environment
        OutputRoot   = $OutputRoot
        CustomerName = $CustomerName
    }

    if ($PSBoundParameters.ContainsKey('Server') -and -not [string]::IsNullOrWhiteSpace($Server)) {
        $invokeParams.Server = $Server
    }

    if ($Domain) {
        $invokeParams.Domain = $Domain
    }

    if ($IncludeSecurity) {
        $invokeParams.IncludeSecurity = $true
    }

    # Capture ALL pipeline output
    $raw = @(Invoke-AdDiscovery @invokeParams)

    # Select last object that contains RunRoot
    $result = $raw |
    Where-Object {
        $_ -and
        $_.PSObject -and
        ($_.PSObject.Properties.Name -contains 'RunRoot')
    } |
    Select-Object -Last 1

    if (-not $result) {
        $types = ($raw | ForEach-Object { $_.GetType().FullName } | Sort-Object -Unique) -join ', '
        throw "Invoke-AdDiscovery did not return a result object with RunRoot. Returned types: $types"
    }

    # Generate discovery index
    $indexPath = Join-Path $result.RunRoot '99_manifest\Discovery.Index.json'

    $tags = @()
    if ($IncludeSecurity) { $tags += 'security' }

    New-ADDiscoveryIndex `
        -RunRoot $result.RunRoot `
        -Environment $Environment `
        -CustomerName $CustomerName `
        -OutputPath $indexPath `
        -Tags $tags

    Write-Host ""
    Write-Host "[OK] Discovery complete" -ForegroundColor Green
    Write-Host "RunRoot: $($result.RunRoot)" -ForegroundColor Yellow
    Write-Host "Index:   $indexPath" -ForegroundColor Yellow
    Write-Host ""

    return $result
}
