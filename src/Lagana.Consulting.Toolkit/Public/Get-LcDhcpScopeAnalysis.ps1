function Get-LcDhcpScopeAnalysis {
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
    $domainDn = (Get-ADDomain -Identity $DomainFqdn -Server $Server -ErrorAction Stop).DistinguishedName
    $configNc = (Get-ADRootDSE -Server $Server).configurationNamingContext

    # Find authorized DHCP servers in the domain
    $dhcpContainer = "CN=NetServices,CN=Services,$configNc"

    try {
      $authorizedServers = Get-ADObject -SearchBase $dhcpContainer -Filter "objectClass -eq 'dHCPClass'" -Properties name, dNSHostName -Server $Server -ErrorAction SilentlyContinue

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
      Write-Verbose "Could not enumerate DHCP servers: $($_.Exception.Message)"
    }

  } catch {
    Write-Warning "Failed to analyze DHCP for $DomainFqdn`: $($_.Exception.Message)"
  }

  return $results
}
