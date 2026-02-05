function Get-AdGpoUserRightsAssignments {
    <#
  .SYNOPSIS
  Parses GPO user rights assignments (e.g., deny logon rights).

  .DESCRIPTION
  Uses Get-GPOReport (XML) to extract User Rights Assignment entries from all GPOs
  in the specified domain. By default, returns the deny logon rights:
  - SeDenyInteractiveLogonRight (Deny log on locally)
  - SeDenyRemoteInteractiveLogonRight (Deny log on through Remote Desktop Services)

  .PARAMETER DomainContext
  Domain context object from Get-AdAdDomainContext. Required.

  .PARAMETER RightName
  One or more user rights assignment names to include.
  Defaults to deny logon locally + deny RDP.

  .PARAMETER IncludeAllRights
  If specified, returns all user rights assignments from GPOs.

  .PARAMETER LogPath
  Optional log path for Write-AdLog.

  .OUTPUTS
  PSCustomObject[] with properties:
  - DomainFqdn, GpoName, GpoId, Section, RightName, Members
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        [string[]]$RightName = @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight'),

        [switch]$IncludeAllRights,

        [string]$LogPath
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    if (-not (Get-Command Get-GPO -ErrorAction SilentlyContinue)) {
        if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message "GroupPolicy module not available; skipping GPO user rights parsing." }
        return @()
    }

    $domain = [string]$DomainContext.DomainFqdn

    $gpos = @()
    try {
        $gpos = @(Get-GPO -All -Domain $domain -ErrorAction Stop)
    } catch {
        if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Failed to enumerate GPOs for {0}. {1}" -f $domain, $_.Exception.Message) }
        return @()
    }

    $results = @()

    foreach ($gpo in $gpos) {
        $report = $null
        try {
            $report = Get-GPOReport -Guid $gpo.Id -Domain $domain -ReportType Xml -ErrorAction Stop
        } catch {
            if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Failed to read GPO report for {0} ({1}). {2}" -f $gpo.DisplayName, $gpo.Id, $_.Exception.Message) }
            continue
        }

        if (-not $report) { continue }

        $xml = $null
        try {
            $xml = [xml]$report
        } catch {
            if ($LogPath) { Write-AdLog -Path $LogPath -Level WARN -Message ("Failed to parse GPO report XML for {0} ({1})." -f $gpo.DisplayName, $gpo.Id) }
            continue
        }

        $nodes = $xml.SelectNodes('//UserRightsAssignment')
        foreach ($node in $nodes) {
            $nameNode = $node.SelectSingleNode('Name')
            if (-not $nameNode) { continue }

            $right = [string]$nameNode.'#text'
            if (-not $IncludeAllRights) {
                if (-not ($RightName -contains $right)) { continue }
            }

            $memberNodes = $node.SelectNodes('Member')
            $members = @()
            foreach ($m in $memberNodes) {
                $n = $m.SelectSingleNode('Name')
                if ($n -and $n.'#text') { $members += [string]$n.'#text' }
                else {
                    $s = $m.SelectSingleNode('Sid')
                    if ($s -and $s.'#text') { $members += [string]$s.'#text' }
                }
            }

            $section = 'Unknown'
            if ($node.SelectSingleNode('ancestor::Computer')) { $section = 'Computer' }
            elseif ($node.SelectSingleNode('ancestor::User')) { $section = 'User' }

            $results += [pscustomobject]@{
                DomainFqdn = $domain
                GpoName    = [string]$gpo.DisplayName
                GpoId      = [string]$gpo.Id
                Section    = $section
                RightName  = $right
                Members    = ($members -join ';')
            }
        }
    }

    return $results
}
