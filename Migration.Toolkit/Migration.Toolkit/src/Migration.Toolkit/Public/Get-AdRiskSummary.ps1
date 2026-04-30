function Get-AdRiskSummary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    $RiskRows
  )

  if (-not $RiskRows) {
    throw "RiskRows cannot be null."
  }

  $RiskRows |
    Group-Object -Property RiskCategory, RiskName, RiskLevel |
    ForEach-Object {
      $parts = $_.Name -split ', '
      [pscustomobject]@{
        RiskCategory = $parts[0]
        RiskName     = $parts[1]
        RiskLevel    = $parts[2]
        Count        = $_.Count
      }
    } |
    Sort-Object RiskLevel, RiskCategory, RiskName
}
