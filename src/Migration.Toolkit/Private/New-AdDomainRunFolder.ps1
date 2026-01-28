function New-AdDomainRunFolder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$RunRoot,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainFqdn
  )

  $root = Resolve-AdPath -Path $RunRoot
  if (-not (Test-Path -LiteralPath $root)) {
    throw "RunRoot does not exist: $root"
  }

  $safeDomain = ConvertTo-AdSafeFolderName -Name $DomainFqdn
  $domainDir = Join-Path $root ("domain_{0}" -f $safeDomain)

  New-AdDirectory -Path $domainDir | Out-Null
  return $domainDir
}
