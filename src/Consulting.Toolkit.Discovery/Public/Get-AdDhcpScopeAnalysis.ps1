function Get-AdDhcpScopeAnalysis {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$DomainFqdn,

    [string]$Server
  )

  if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available. Install RSAT AD tools."
  }

  $results = @()

  try {
    $ctx = Get-AdAdDomainContext -DomainFqdn $DomainFqdn -Server $Server
    $Server = $ctx.Server
    $configNc = (Get-ADRootDSE -Server $Server -ErrorAction Stop).configurationNamingContext

    # Find authorized DHCP servers in the domain
    $dhcpContainer = "CN=NetServices,CN=Services,$configNc"

    try {
      $authorizedServers = @(Get-ADObject -SearchBase $dhcpContainer -Filter "objectClass -eq 'dHCPClass'" -Properties name, dNSHostName -Server $Server -ErrorAction Stop)

      foreach ($dhcpServer in $authorizedServers) {
        $serverName = if ($dhcpServer.dNSHostName) { $dhcpServer.dNSHostName } else { $dhcpServer.name }

        # Note: Actual scope utilization requires Get-DhcpServerv4Scope cmdlet which needs DHCP PowerShell module
        # and remote access to DHCP server. This inventory focuses on AD-registered DHCP servers.

        $results += [pscustomobject]@{
          DhcpServerName = $serverName
          DN             = $dhcpServer.DistinguishedName
          DomainFqdn     = $DomainFqdn
          Status         = 'Authorized'
          Notes          = 'AD-authorized DHCP server (scope details require DHCP module)'
        }
      }

      if ($authorizedServers.Count -eq 0) {
        $results += [pscustomobject]@{
          DhcpServerName = 'None'
          DN             = ''
          DomainFqdn     = $DomainFqdn
          Status         = 'No Authorized Servers'
          Notes          = 'No DHCP servers found in AD authorization list'
        }
      }

    } catch {
      throw
    }

  } catch {
    throw
  }

  return $results
}
