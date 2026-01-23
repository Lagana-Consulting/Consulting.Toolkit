Describe "Lagana.Consulting.Toolkit" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\src\Lagana.Consulting.Toolkit"
    Import-Module $modulePath -Force
  }

  It "Exports expected server-side commands" {
    $cmds = Get-Command -Module Lagana.Consulting.Toolkit | Select-Object -ExpandProperty Name
    ($cmds -contains "New-LcLog") | Should Be $true
    ($cmds -contains "Write-LcLog") | Should Be $true
    ($cmds -contains "Export-LcCsv") | Should Be $true
    ($cmds -contains "Get-LcAdForest") | Should Be $true
    ($cmds -contains "New-LcAdmtRunLayout") | Should Be $true
    ($cmds -contains "Test-LcAdmtPrereqs") | Should Be $true
  }

  It "Does not export client-side analysis functions" {
    $cmds = Get-Command -Module Lagana.Consulting.Toolkit | Select-Object -ExpandProperty Name
    ($cmds -contains "New-LcComprehensiveAssessmentReport") | Should Be $false
    ($cmds -contains "Export-LcCsvSafe") | Should Be $false
    ($cmds -contains "Invoke-LcDiscoveryAnalysis") | Should Be $false
  }
}

Describe "Lagana.Consulting.Toolkit.Analysis" {
  BeforeAll {
    # Skip if not PowerShell 7+
    if ($PSVersionTable.PSVersion.Major -lt 7) {
      Set-ItResult -Skipped -Because "Analysis module requires PowerShell 7+"
      return
    }

    $coreModulePath = Join-Path $PSScriptRoot "..\src\Lagana.Consulting.Toolkit"
    $analysisModulePath = Join-Path $PSScriptRoot "..\src\Lagana.Consulting.Toolkit.Analysis"
    Import-Module $coreModulePath -Force
    Import-Module $analysisModulePath -Force
  }

  It "Exports expected analysis commands" -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    $cmds = Get-Command -Module Lagana.Consulting.Toolkit.Analysis | Select-Object -ExpandProperty Name
    ($cmds -contains "Export-LcCsvSafe") | Should Be $true
    ($cmds -contains "Get-LcSchemaDefinitions") | Should Be $true
    ($cmds -contains "New-LcComprehensiveAssessmentReport") | Should Be $true
    ($cmds -contains "Invoke-LcDiscoveryAnalysis") | Should Be $true
  }
}
