function Get-LcFsmoRoleAvailability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ForestName
    )

    $forest = Get-LcAdForest -ForestName $ForestName
    $domains = Get-LcAdDomains -Forest $forest

    $results = @()

    # Forest-level FSMO roles
    $results += [pscustomobject]@{
        Scope       = 'Forest'
        Role        = 'SchemaMaster'
        Holder      = [string]$forest.SchemaMaster
        IsAvailable = (Test-Connection -ComputerName $forest.SchemaMaster -Count 1 -Quiet -ErrorAction SilentlyContinue)
    }

    $results += [pscustomobject]@{
        Scope       = 'Forest'
        Role        = 'DomainNamingMaster'
        Holder      = [string]$forest.DomainNamingMaster
        IsAvailable = (Test-Connection -ComputerName $forest.DomainNamingMaster -Count 1 -Quiet -ErrorAction SilentlyContinue)
    }

    # Domain-level FSMO roles
    foreach ($domainFqdn in $domains) {
        $ctx = Get-LcAdDomainContext -DomainFqdn $domainFqdn
        $domainSummary = Get-LcAdDomainSummary -DomainContext $ctx

        $results += [pscustomobject]@{
            Scope       = $domainFqdn
            Role        = 'PdcEmulator'
            Holder      = [string]$domainSummary.PdcEmulator
            IsAvailable = (Test-Connection -ComputerName $domainSummary.PdcEmulator -Count 1 -Quiet -ErrorAction SilentlyContinue)
        }

        $results += [pscustomobject]@{
            Scope       = $domainFqdn
            Role        = 'RidMaster'
            Holder      = [string]$domainSummary.RidMaster
            IsAvailable = (Test-Connection -ComputerName $domainSummary.RidMaster -Count 1 -Quiet -ErrorAction SilentlyContinue)
        }

        $results += [pscustomobject]@{
            Scope       = $domainFqdn
            Role        = 'InfrastructureMaster'
            Holder      = [string]$domainSummary.InfrastructureMaster
            IsAvailable = (Test-Connection -ComputerName $domainSummary.InfrastructureMaster -Count 1 -Quiet -ErrorAction SilentlyContinue)
        }
    }

    return $results
}
