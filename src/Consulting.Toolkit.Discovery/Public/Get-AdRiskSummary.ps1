function Get-AdRiskSummary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyCollection()][object[]]$RiskRows
  )

  $RiskRows |
    Group-Object -Property RiskCategory, RiskName, RiskLevel |
    ForEach-Object {
      $risk = $_.Group[0]
      [pscustomobject]@{
        RiskCategory = $risk.RiskCategory
        RiskName     = $risk.RiskName
        RiskLevel    = $risk.RiskLevel
        Count        = $_.Count
      }
    } |
    Sort-Object RiskLevel, RiskCategory, RiskName
}
