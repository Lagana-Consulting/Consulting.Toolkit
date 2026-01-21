function Get-LcAdDomainSummary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    $DomainContext
  )

  # DomainContext is from Get-LcAdDomainContext
  [pscustomobject]@{
    DomainFqdn           = [string]$DomainContext.DomainFqdn
    DomainDn             = [string]$DomainContext.DomainDn
    NetBIOSName          = [string]$DomainContext.NetBiosName
    DomainMode           = [string]$DomainContext.DomainMode
    PdcEmulator          = [string]$DomainContext.PdcEmulator
    RidMaster            = [string]$DomainContext.RidMaster
    InfrastructureMaster = [string]$DomainContext.InfrastructureMaster
    ServerUsed           = [string]$DomainContext.Server
  }
}
