function Get-AdGroupMembershipDetails {
    <#
    .SYNOPSIS
    Collects group membership detail signals for empty, single-member, and risky-member groups.

    .DESCRIPTION
    Enumerates groups in a domain and returns three datasets:
    - EmptyGroups: groups with no direct members
    - SingleMemberGroups: groups with exactly one direct member
    - GroupsWithDisabledOrInactiveMembers: direct members that are disabled or inactive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        [int]$InactiveDays = 180
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    if (-not (Get-Command Get-ADGroup -ErrorAction SilentlyContinue)) {
        throw "ActiveDirectory module not available (Get-ADGroup missing)."
    }

    $domain = [string]$DomainContext.DomainFqdn
    $server = [string]$DomainContext.Server
    $now = Get-Date

    $groups = @()
    try {
        $groups = @(Get-ADGroup -Filter * -Server $server -Properties Members, GroupCategory, GroupScope, WhenCreated, WhenChanged, Description, objectSid -ErrorAction Stop | Sort-Object Name)
    }
    catch {
        try {
            $groups = @(Get-ADGroup -Filter * -Properties Members, GroupCategory, GroupScope, WhenCreated, WhenChanged, Description, objectSid -ErrorAction Stop | Sort-Object Name)
        }
        catch {
            throw "Failed to enumerate groups for $domain. $($_.Exception.Message)"
        }
    }

    $emptyGroups = New-Object System.Collections.Generic.List[object]
    $singleMemberGroups = New-Object System.Collections.Generic.List[object]
    $disabledOrInactiveMembers = New-Object System.Collections.Generic.List[object]

    foreach ($group in @($groups | Where-Object { -not (Test-AdBuiltInGroup -Group $_) })) {
        $members = @($group.Members | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $memberCount = $members.Count

        if ($memberCount -eq 0) {
            [void]$emptyGroups.Add((New-AdGroupMembershipSummaryRow -DomainFqdn $domain -Group $group -MemberCount 0))
            continue
        }

        $memberDetails = New-Object System.Collections.Generic.List[object]
        foreach ($memberDn in $members) {
            $member = Get-AdGroupMembershipMemberDetail -DomainFqdn $domain -Server $server -Group $group -MemberDn ([string]$memberDn) -Now $now -InactiveDays $InactiveDays
            [void]$memberDetails.Add($member)

            if ($member.IsDisabled -or $member.IsInactive) {
                [void]$disabledOrInactiveMembers.Add($member)
            }
        }

        if ($memberCount -eq 1) {
            $onlyMember = $memberDetails | Select-Object -First 1
            [void]$singleMemberGroups.Add((New-AdGroupMembershipSingleMemberRow -DomainFqdn $domain -Group $group -MemberCount $memberCount -Member $onlyMember))
        }
    }

    return [pscustomobject]@{
        EmptyGroups                         = @($emptyGroups.ToArray())
        SingleMemberGroups                  = @($singleMemberGroups.ToArray())
        GroupsWithDisabledOrInactiveMembers = @($disabledOrInactiveMembers.ToArray())
    }
}
