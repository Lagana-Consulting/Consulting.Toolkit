BeforeAll {
  $modulePath = Join-Path $PSScriptRoot "..\src\Lagana.Consulting.Toolkit"
  Import-Module $modulePath -Force
}

Describe "Lagana.Consulting.Toolkit" {
  It "Exports expected public commands" {
    $cmds = Get-Command -Module Lagana.Consulting.Toolkit | Select-Object -ExpandProperty Name
    $cmds | Should -Contain "New-LcLog"
    $cmds | Should -Contain "Write-LcLog"
    $cmds | Should -Contain "Export-LcCsv"
    $cmds | Should -Contain "Confirm-LcTenant"
    $cmds | Should -Contain "Connect-LcGraph"
  }
}
