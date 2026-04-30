function Resolve-AdAssessmentTemplatePath {
    [CmdletBinding()]
    param(
        [string]$TemplatePath,
        [switch]$UseBundledDiscoveryTemplate,
        [switch]$UseBundledSummaryTemplate
    )

    if ($UseBundledDiscoveryTemplate -and $UseBundledSummaryTemplate) {
        throw "Specify only one bundled template switch."
    }

    $configRoot = Join-Path $PSScriptRoot '..\config'

    if ($UseBundledDiscoveryTemplate) {
        $TemplatePath = Join-Path $configRoot 'Template - Discovery and Assessment Findings Report V1.0 - Quest 2025 style.docx'
    }
    elseif ($UseBundledSummaryTemplate) {
        $TemplatePath = Join-Path $configRoot 'Template - Assessment Summary and Migration Process - Quest 2025 style.docx'
    }

    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        throw "A template path was not provided. Use -TemplatePath or one of the bundled template switches."
    }

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw "Template not found: $TemplatePath"
    }

    return (Resolve-Path -LiteralPath $TemplatePath).Path
}
