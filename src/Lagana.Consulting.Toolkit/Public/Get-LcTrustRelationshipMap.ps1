function Get-LcTrustRelationshipMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Forest
    )

    if (-not (Get-Command Get-ADTrust -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available. Install RSAT AD tools."
    }

    $results = @()

    try {
        $domains = Get-LcAdDomains -Forest $Forest

        foreach ($domainFqdn in $domains) {
            try {
                $trusts = Get-ADTrust -Filter * -Server $domainFqdn -ErrorAction Stop

                foreach ($trust in $trusts) {
                    # Determine trust transitivity
                    $isTransitive = if ($trust.TrustAttributes -band 0x00000001) { $false } else { $true }

                    # Determine trust direction
                    $direction = switch ($trust.Direction) {
                        0 { 'Disabled' }
                        1 { 'Inbound' }
                        2 { 'Outbound' }
                        3 { 'Bidirectional' }
                        default { 'Unknown' }
                    }

                    # Determine trust type
                    $trustType = switch ($trust.TrustType) {
                        1 { 'Downlevel (NT4)' }
                        2 { 'Uplevel (AD)' }
                        3 { 'MIT Kerberos' }
                        4 { 'DCE' }
                        default { 'Unknown' }
                    }

                    # Security assessment
                    $securityNotes = @()
                    if (-not $isTransitive) { $securityNotes += 'Non-transitive' }
                    if ($trust.SIDFilteringQuarantined) { $securityNotes += 'SID filtering enabled' }
                    if ($trust.SelectiveAuthentication) { $securityNotes += 'Selective authentication' }

                    $results += [pscustomobject]@{
                        SourceDomain        = $domainFqdn
                        TargetDomain        = $trust.Target
                        Direction           = $direction
                        TrustType           = $trustType
                        IsTransitive        = $isTransitive
                        SIDFilteringEnabled = [bool]$trust.SIDFilteringQuarantined
                        SelectiveAuth       = [bool]$trust.SelectiveAuthentication
                        WhenCreated         = $trust.Created
                        WhenChanged         = $trust.Modified
                        SecurityNotes       = ($securityNotes -join '; ')
                        Recommendation      = if ($trustType -eq 'Downlevel (NT4)') { 'Upgrade or remove legacy trust' }
                        elseif (-not $trust.SIDFilteringQuarantined -and $direction -ne 'Outbound') { 'Consider enabling SID filtering for security' }
                        else { 'No immediate action' }
                    }
                }
            } catch {
                Write-Warning "Failed to enumerate trusts for $($domainFqdn): $($_.Exception.Message)"
            }
        }

    } catch {
        Write-Warning "Failed to map trust relationships: $($_.Exception.Message)"
    }

    return $results
}
