function New-LcDomainRunFolder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RunRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainFqdn
  )

  $root = Resolve-LcPath -Path $RunRoot
  if (-not (Test-Path -LiteralPath $root)) {
    throw "RunRoot does not exist: $root"
  }

  $safeDomain = ConvertTo-LcSafeFolderName -Name $DomainFqdn
  $domainDir = Join-Path $root ("domain_{0}" -f $safeDomain)

  New-LcDirectory -Path $domainDir | Out-Null
  return $domainDir
}
