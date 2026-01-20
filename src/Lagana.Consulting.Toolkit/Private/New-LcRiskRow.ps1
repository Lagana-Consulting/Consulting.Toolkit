function New-LcRiskRow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Scope,
    [Parameter(Mandatory)][string]$Domain,
    [Parameter(Mandatory)][string]$ObjectType,
    [Parameter(Mandatory)][string]$ObjectName,
    [string]$ObjectId,
    [Parameter(Mandatory)][string]$RiskCategory,
    [Parameter(Mandatory)][string]$RiskName,
    [ValidateSet('Low','Medium','High')][string]$RiskLevel,
    [string]$Details
  )

  [pscustomobject]@{
    Scope        = $Scope
    Domain       = $Domain
    ObjectType   = $ObjectType
    ObjectName   = $ObjectName
    ObjectId     = $ObjectId
    RiskCategory = $RiskCategory
    RiskName     = $RiskName
    RiskLevel    = $RiskLevel
    Details      = $Details
  }
}
