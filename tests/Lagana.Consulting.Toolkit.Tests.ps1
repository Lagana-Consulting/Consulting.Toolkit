Describe "Lagana.Consulting.Toolkit" {
  BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\src\Lagana.Consulting.Toolkit"
    Import-Module $modulePath -Force
  }

  It "Exports expected public commands" {
    $cmds = Get-Command -Module Lagana.Consulting.Toolkit | Select-Object -ExpandProperty Name
    ($cmds -contains "New-LcLog") | Should Be $true
    ($cmds -contains "Write-LcLog") | Should Be $true
    ($cmds -contains "Export-LcCsv") | Should Be $true
    ($cmds -contains "Confirm-LcTenant") | Should Be $true
    ($cmds -contains "Connect-LcGraph") | Should Be $true
    ($cmds -contains "New-LcAdmtRunLayout") | Should Be $true
    ($cmds -contains "Test-LcAdmtPrereqs") | Should Be $true
  }
}
