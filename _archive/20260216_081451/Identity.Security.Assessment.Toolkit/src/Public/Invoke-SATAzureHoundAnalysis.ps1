<#
.SYNOPSIS
  Analyzes AzureHound JSON output and produces Entra security findings.

.DESCRIPTION
  Consumes an AzureHound export JSON file (meta.type = azure), evaluates
  high-risk identity and application patterns, and writes findings/evidence
  into the toolkit assessment structure under Evidence\Entra.

.PARAMETER InputPath
  Path to the AzureHound JSON output file.

.PARAMETER Profile
  Assessment profile used for output metadata.

.PARAMETER AssessmentPath
  Existing assessment folder. If omitted, a new one is created.

.PARAMETER OutputRoot
  Root folder for new assessment output when AssessmentPath is not supplied.

.PARAMETER SnapshotTimestamp
  Optional timestamp used in evidence file names (yyyyMMddHHmmss).

.PARAMETER ConfigRoot
  Optional config folder containing severity_map.json and thresholds.json.

.PARAMETER CredentialExpiryDays
  Number of days used to flag application credentials as expiring soon.

.PARAMETER BreakGlassStaleDays
  Number of days used to flag break-glass accounts as stale.

.EXAMPLE
  Invoke-SATAzureHoundAnalysis -InputPath 'D:\Bloodhound\azurehound-output.json'

  Runs analysis with default profile and default output root.

.EXAMPLE
  Invoke-SATAzureHoundAnalysis -InputPath 'D:\Bloodhound\azurehound-output.json' -Profile Standard -OutputRoot '.\output'

  Runs analysis with the Standard profile and writes a new timestamped assessment under .\output.

.EXAMPLE
  Invoke-SATAzureHoundAnalysis -InputPath 'D:\Bloodhound\azurehound-output.json' -AssessmentPath '.\output\20260210_062410' -CredentialExpiryDays 60 -BreakGlassStaleDays 14

  Appends Entra findings/evidence to an existing assessment path using tighter credential and break-glass thresholds.
#>
function Invoke-SATAzureHoundAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$AssessmentPath,
        [string]$OutputRoot,
        [string]$SnapshotTimestamp,
        [string]$ConfigRoot,

        [int]$CredentialExpiryDays = 90,
        [int]$BreakGlassStaleDays = 30
    )

    Set-StrictMode -Version Latest

    if (-not (Test-Path $InputPath)) {
        throw "InputPath not found: $InputPath"
    }

    if (-not $AssessmentPath) {
        $AssessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    }

    if (-not $SnapshotTimestamp) {
        $SnapshotTimestamp = (Get-Date -Format 'yyyyMMddHHmmss')
    }

    $logsDir = Join-Path $AssessmentPath 'Logs'
    if (-not (Test-Path $logsDir)) { New-Item -Path $logsDir -ItemType Directory -Force | Out-Null }
    $logPath = Join-Path $logsDir 'RunLog.txt'
    Write-SATLog -Message "Invoke-SATAzureHoundAnalysis started. Profile=$Profile InputPath=$InputPath" -LogPath $logPath

    $evidenceRoot = Join-Path $AssessmentPath 'Evidence'
    $entraDir = Join-Path $evidenceRoot 'Entra'
    if (-not (Test-Path $entraDir)) { New-Item -Path $entraDir -ItemType Directory -Force | Out-Null }

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $ConfigRoot) {
        $ConfigRoot = Join-Path $moduleRoot 'config'
    }

    $severityMapPath = Join-Path $ConfigRoot 'severity_map.json'
    $thresholdsPath = Join-Path $ConfigRoot 'thresholds.json'

    $severityMap = @{
        Informational = 0
        Low           = 1
        Medium        = 2
        High          = 3
        Critical      = 4
    }

    if (Test-Path $severityMapPath) {
        $map = Get-Content -Path $severityMapPath -Raw | ConvertFrom-Json
        foreach ($key in $map.PSObject.Properties.Name) {
            $severityMap[$key] = [int]$map.$key
        }
    }

    $thresholds = [pscustomobject]@{}
    if (Test-Path $thresholdsPath) {
        $thresholds = Get-Content -Path $thresholdsPath -Raw | ConvertFrom-Json
    }

    function Get-ThresholdSet {
        param (
            [string]$Name,
            [hashtable]$Fallback
        )

        $set = $thresholds.$Name
        if (-not $set) {
            return $Fallback
        }

        return @{
            Low    = [int]$set.Low
            Medium = [int]$set.Medium
            High   = [int]$set.High
        }
    }

    function Get-SeverityFromCount {
        param (
            [int]$Count,
            [hashtable]$ThresholdSet
        )

        if ($Count -ge $ThresholdSet.High) { return 'High' }
        if ($Count -ge $ThresholdSet.Medium) { return 'Medium' }
        if ($Count -ge $ThresholdSet.Low) { return 'Low' }
        return 'Informational'
    }

    function New-Finding {
        param (
            [string]$FindingId,
            [string]$Category,
            [string]$Title,
            [string]$Severity,
            [string]$Asset,
            [string]$Domain,
            [int]$EvidenceCount,
            [string]$EvidenceSource,
            [string]$EvidenceRef,
            [string]$Recommendation,
            [string]$PolicyRef,
            [string]$Profile,
            [string]$Tool
        )

        $riskScore = 0
        if ($Severity -and $severityMap.ContainsKey($Severity)) {
            $riskScore = [int]$severityMap[$Severity]
        }

        [pscustomobject]@{
            FindingId      = $FindingId
            Category       = $Category
            Title          = $Title
            Severity       = $Severity
            RiskScore      = $riskScore
            Asset          = $Asset
            Domain         = $Domain
            EvidenceCount  = $EvidenceCount
            EvidenceSource = $EvidenceSource
            EvidenceRef    = $EvidenceRef
            Recommendation = $Recommendation
            PolicyRef      = $PolicyRef
            Profile        = $Profile
            Tool           = $Tool
            Timestamp      = (Get-Date -Format 's')
        }
    }

    function Add-EvidenceIndex {
        param (
            [System.Collections.Generic.List[object]]$Index,
            [string]$FindingId,
            [string]$EvidencePath,
            [string]$Domain,
            [string]$Notes
        )

        $fileName = Split-Path $EvidencePath -Leaf
        $ext = [System.IO.Path]::GetExtension($fileName).TrimStart('.').ToLowerInvariant()
        $type = if ($ext) { $ext } else { 'unknown' }

        $Index.Add([pscustomobject]@{
                FindingId    = $FindingId
                EvidenceFile = $fileName
                EvidenceType = $type
                Domain       = $Domain
                Notes        = $Notes
            })
    }

    function New-EmptyEvidence {
        param(
            [string]$Path,
            [string[]]$Headers
        )

        New-SATCsv -Path $Path -Headers $Headers
    }

    function Test-HighPrivilegeRoleValue {
        param([string]$Value)

        if (-not $Value) { return $false }

        $exact = @(
            'Directory.Read.All',
            'Directory.ReadWrite.All',
            'RoleManagement.ReadWrite.Directory',
            'AppRoleAssignment.ReadWrite.All',
            'Application.ReadWrite.All',
            'Policy.ReadWrite.ConditionalAccess',
            'Group.ReadWrite.All',
            'User.ReadWrite.All',
            'ADSynchronization.ReadWrite.All'
        )

        if ($exact -contains $Value) { return $true }
        if ($Value -like '*.ReadWrite.All') { return $true }
        if ($Value -like 'PasswordWriteback.*') { return $true }
        return $false
    }

    $json = Get-Content -Path $InputPath -Raw | ConvertFrom-Json
    $records = @()
    if ($json.PSObject.Properties['data']) {
        $records = @($json.data)
    }

    if ($records.Count -eq 0) {
        throw "Input JSON contains no data records: $InputPath"
    }

    $tenant = $records | Where-Object { $_.kind -eq 'AZTenant' } | Select-Object -First 1 -ExpandProperty data
    $tenantName = if ($tenant -and $tenant.displayName) { [string]$tenant.displayName } else { 'UnknownTenant' }
    $tenantId = if ($tenant -and $tenant.tenantId) { [string]$tenant.tenantId } else { '' }

    $users = @($records | Where-Object { $_.kind -eq 'AZUser' } | Select-Object -ExpandProperty data)
    $apps = @($records | Where-Object { $_.kind -eq 'AZApp' } | Select-Object -ExpandProperty data)
    $appOwners = @($records | Where-Object { $_.kind -eq 'AZAppOwner' } | Select-Object -ExpandProperty data)
    $servicePrincipals = @($records | Where-Object { $_.kind -eq 'AZServicePrincipal' } | Select-Object -ExpandProperty data)
    $servicePrincipalOwners = @($records | Where-Object { $_.kind -eq 'AZServicePrincipalOwner' } | Select-Object -ExpandProperty data)
    $roleAssignmentsRaw = @($records | Where-Object { $_.kind -eq 'AZRoleAssignment' } | Select-Object -ExpandProperty data)
    $appRoleAssignments = @($records | Where-Object { $_.kind -eq 'AZAppRoleAssignment' } | Select-Object -ExpandProperty data)

    $idIndex = @{}
    foreach ($u in $users) {
        if ($u.id) { $idIndex[[string]$u.id] = [pscustomobject]@{ Kind = 'AZUser'; Ref = $u } }
    }
    foreach ($sp in $servicePrincipals) {
        if ($sp.id) { $idIndex[[string]$sp.id] = [pscustomobject]@{ Kind = 'AZServicePrincipal'; Ref = $sp } }
    }

    $appByAppId = @{}
    foreach ($app in $apps) {
        if ($app.appId) { $appByAppId[[string]$app.appId] = $app }
    }

    $servicePrincipalById = @{}
    foreach ($sp in $servicePrincipals) {
        if ($sp.id) { $servicePrincipalById[[string]$sp.id] = $sp }
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $evidenceIndex = New-Object System.Collections.Generic.List[object]
    $evidenceFiles = New-Object System.Collections.Generic.List[string]

    # 1) Guest Global Admins
    $globalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'
    $globalAdminEntry = $roleAssignmentsRaw | Where-Object { $_.roleDefinitionId -eq $globalAdminRoleId } | Select-Object -First 1
    $globalAdminAssignments = @()
    if ($globalAdminEntry -and $globalAdminEntry.roleAssignments) {
        $globalAdminAssignments = @($globalAdminEntry.roleAssignments)
    }

    $guestGaRows = New-Object System.Collections.Generic.List[object]
    foreach ($assignment in $globalAdminAssignments) {
        if (-not $assignment.principalId) { continue }
        $principalId = [string]$assignment.principalId
        if (-not $idIndex.ContainsKey($principalId)) { continue }
        $resolved = $idIndex[$principalId]
        if ($resolved.Kind -ne 'AZUser') { continue }
        $user = $resolved.Ref
        if ($user.userType -ne 'Guest') { continue }

        $guestGaRows.Add([pscustomobject]@{
                AssignmentId      = [string]$assignment.id
                PrincipalId       = $principalId
                DisplayName       = [string]$user.displayName
                UserPrincipalName = [string]$user.userPrincipalName
                UserType          = [string]$user.userType
                DirectoryScopeId  = [string]$assignment.directoryScopeId
                TenantId          = $tenantId
            })
    }

    $guestGaCsv = Join-Path $entraDir ("azurehound-guest-global-admins-{0}.csv" -f $SnapshotTimestamp)
    if ($guestGaRows.Count -gt 0) {
        $guestGaRows | Export-Csv -Path $guestGaCsv -NoTypeInformation -Encoding UTF8
        $sev = Get-SeverityFromCount -Count $guestGaRows.Count -ThresholdSet (Get-ThresholdSet -Name 'GuestGlobalAdmins' -Fallback @{ Low = 1; Medium = 2; High = 3 })
        $findings.Add((New-Finding -FindingId 'ENTRA-001' -Category 'Privilege Management' -Title 'Guest accounts with Global Administrator role' -Severity $sev -Asset $tenantName -Domain $tenantName -EvidenceCount $guestGaRows.Count -EvidenceSource 'AzureHound' -EvidenceRef (Split-Path $guestGaCsv -Leaf) -Recommendation 'Remove direct guest Global Administrator assignments. Use least privilege and JIT/PIM with strict review and expiration.' -PolicyRef 'Least privilege / external identity governance' -Profile $Profile -Tool 'Identity.Security.Assessment.Toolkit'))
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'ENTRA-001' -EvidencePath $guestGaCsv -Domain $tenantName -Notes 'Guest principals assigned to Global Administrator'
    } else {
        New-EmptyEvidence -Path $guestGaCsv -Headers @('AssignmentId', 'PrincipalId', 'DisplayName', 'UserPrincipalName', 'UserType', 'DirectoryScopeId', 'TenantId')
    }
    $evidenceFiles.Add($guestGaCsv)

    # 2) Break-glass inactivity
    $gaPrincipalSet = @{}
    foreach ($assignment in $globalAdminAssignments) {
        if ($assignment.principalId) { $gaPrincipalSet[[string]$assignment.principalId] = $true }
    }

    $breakGlassRows = New-Object System.Collections.Generic.List[object]
    foreach ($user in $users) {
        $name = if ($user.displayName) { [string]$user.displayName } else { '' }
        $upn = if ($user.userPrincipalName) { [string]$user.userPrincipalName } else { '' }
        $isBreakGlass = ($name -match '(?i)break.?glass|bglass|emergency') -or ($upn -match '(?i)break.?glass|bglass|emergency')
        if (-not $isBreakGlass) { continue }

        $lastSignIn = $null
        if ($user.lastSuccessfulSignInDateTime) {
            try { $lastSignIn = [datetime]$user.lastSuccessfulSignInDateTime } catch { $lastSignIn = $null }
        }

        $daysSinceSignIn = if ($lastSignIn) { [int]([datetime]::UtcNow - $lastSignIn.ToUniversalTime()).TotalDays } else { 999999 }
        $isStale = $daysSinceSignIn -ge $BreakGlassStaleDays
        $isGa = $false
        if ($user.id -and $gaPrincipalSet.ContainsKey([string]$user.id)) { $isGa = $true }

        $breakGlassRows.Add([pscustomobject]@{
                PrincipalId              = [string]$user.id
                DisplayName              = $name
                UserPrincipalName        = $upn
                AccountEnabled           = [bool]$user.accountEnabled
                IsGlobalAdministrator    = $isGa
                LastSuccessfulSignInUtc  = if ($lastSignIn) { $lastSignIn.ToString('u') } else { $null }
                DaysSinceSuccessfulSignIn = $daysSinceSignIn
                IsStale                  = $isStale
                StaleThresholdDays       = $BreakGlassStaleDays
                TenantId                 = $tenantId
            })
    }

    $breakGlassCsv = Join-Path $entraDir ("azurehound-breakglass-review-{0}.csv" -f $SnapshotTimestamp)
    if ($breakGlassRows.Count -gt 0) {
        $breakGlassRows | Export-Csv -Path $breakGlassCsv -NoTypeInformation -Encoding UTF8
        $staleCount = @($breakGlassRows | Where-Object { $_.IsStale }).Count
        if ($staleCount -gt 0) {
            $sev = Get-SeverityFromCount -Count $staleCount -ThresholdSet (Get-ThresholdSet -Name 'BreakGlassStaleAccounts' -Fallback @{ Low = 1; Medium = 2; High = 3 })
            $findings.Add((New-Finding -FindingId 'ENTRA-002' -Category 'Identity Resilience' -Title 'Break-glass accounts are stale or not recently validated' -Severity $sev -Asset $tenantName -Domain $tenantName -EvidenceCount $staleCount -EvidenceSource 'AzureHound' -EvidenceRef (Split-Path $breakGlassCsv -Leaf) -Recommendation 'Validate break-glass sign-in procedure on a controlled cadence, monitor sign-ins, and document emergency-access controls.' -PolicyRef 'Emergency access account standard' -Profile $Profile -Tool 'Identity.Security.Assessment.Toolkit'))
            Add-EvidenceIndex -Index $evidenceIndex -FindingId 'ENTRA-002' -EvidencePath $breakGlassCsv -Domain $tenantName -Notes 'Break-glass account activity review'
        }
    } else {
        New-EmptyEvidence -Path $breakGlassCsv -Headers @('PrincipalId', 'DisplayName', 'UserPrincipalName', 'AccountEnabled', 'IsGlobalAdministrator', 'LastSuccessfulSignInUtc', 'DaysSinceSuccessfulSignIn', 'IsStale', 'StaleThresholdDays', 'TenantId')
    }
    $evidenceFiles.Add($breakGlassCsv)

    # 3) Ownerless app registrations
    $ownerlessAppRows = New-Object System.Collections.Generic.List[object]
    foreach ($ownerRow in $appOwners) {
        $ownerCount = if ($ownerRow.owners) { @($ownerRow.owners).Count } else { 0 }
        if ($ownerCount -gt 0) { continue }
        if (-not $ownerRow.appId) { continue }
        $appId = [string]$ownerRow.appId
        $app = $null
        if ($appByAppId.ContainsKey($appId)) { $app = $appByAppId[$appId] }

        $ownerlessAppRows.Add([pscustomobject]@{
                AppId           = $appId
                DisplayName     = if ($app) { [string]$app.displayName } else { $null }
                CreatedDateTime = if ($app) { [string]$app.createdDateTime } else { $null }
                SignInAudience  = if ($app) { [string]$app.signInAudience } else { $null }
                OwnerCount      = 0
                TenantId        = $tenantId
            })
    }

    $ownerlessAppsCsv = Join-Path $entraDir ("azurehound-ownerless-apps-{0}.csv" -f $SnapshotTimestamp)
    if ($ownerlessAppRows.Count -gt 0) {
        $ownerlessAppRows | Export-Csv -Path $ownerlessAppsCsv -NoTypeInformation -Encoding UTF8
        $sev = Get-SeverityFromCount -Count $ownerlessAppRows.Count -ThresholdSet (Get-ThresholdSet -Name 'OwnerlessApps' -Fallback @{ Low = 1; Medium = 3; High = 5 })
        $findings.Add((New-Finding -FindingId 'ENTRA-003' -Category 'Application Governance' -Title 'App registrations without owners' -Severity $sev -Asset $tenantName -Domain $tenantName -EvidenceCount $ownerlessAppRows.Count -EvidenceSource 'AzureHound' -EvidenceRef (Split-Path $ownerlessAppsCsv -Leaf) -Recommendation 'Assign at least two accountable owners for each app registration and enforce owner review lifecycle.' -PolicyRef 'Application identity governance' -Profile $Profile -Tool 'Identity.Security.Assessment.Toolkit'))
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'ENTRA-003' -EvidencePath $ownerlessAppsCsv -Domain $tenantName -Notes 'Applications with no owners'
    } else {
        New-EmptyEvidence -Path $ownerlessAppsCsv -Headers @('AppId', 'DisplayName', 'CreatedDateTime', 'SignInAudience', 'OwnerCount', 'TenantId')
    }
    $evidenceFiles.Add($ownerlessAppsCsv)

    # 4) High-privilege application permissions
    $highPrivRoleRows = New-Object System.Collections.Generic.List[object]
    foreach ($assignment in $appRoleAssignments) {
        $resourceId = if ($assignment.resourceId) { [string]$assignment.resourceId } else { '' }
        $appRoleId = if ($assignment.appRoleId) { [string]$assignment.appRoleId } else { '' }
        if (-not $resourceId -or -not $appRoleId) { continue }
        if (-not $servicePrincipalById.ContainsKey($resourceId)) { continue }

        $resourceSp = $servicePrincipalById[$resourceId]
        $role = $null
        if ($resourceSp.appRoles) {
            $role = @($resourceSp.appRoles | Where-Object { $_.id -eq $appRoleId } | Select-Object -First 1)
            if ($role.Count -gt 0) { $role = $role[0] } else { $role = $null }
        }

        $roleValue = if ($role -and $role.value) { [string]$role.value } else { '' }
        if (-not (Test-HighPrivilegeRoleValue -Value $roleValue)) { continue }

        $highPrivRoleRows.Add([pscustomobject]@{
                PrincipalDisplayName = [string]$assignment.principalDisplayName
                PrincipalId          = [string]$assignment.principalId
                PrincipalType        = [string]$assignment.principalType
                ResourceDisplayName  = [string]$assignment.resourceDisplayName
                ResourceId           = $resourceId
                AppRoleId            = $appRoleId
                RoleValue            = $roleValue
                RoleDisplayName      = if ($role -and $role.displayName) { [string]$role.displayName } else { $null }
                AssignedDateTime     = [string]$assignment.createdDateTime
                TenantId             = $tenantId
            })
    }

    $highPrivAppsCsv = Join-Path $entraDir ("azurehound-high-priv-app-perms-{0}.csv" -f $SnapshotTimestamp)
    if ($highPrivRoleRows.Count -gt 0) {
        $highPrivRoleRows | Export-Csv -Path $highPrivAppsCsv -NoTypeInformation -Encoding UTF8
        $sev = Get-SeverityFromCount -Count $highPrivRoleRows.Count -ThresholdSet (Get-ThresholdSet -Name 'HighPrivAppPermissions' -Fallback @{ Low = 1; Medium = 2; High = 4 })
        $findings.Add((New-Finding -FindingId 'ENTRA-004' -Category 'Application Permissions' -Title 'High-privilege application permissions detected' -Severity $sev -Asset $tenantName -Domain $tenantName -EvidenceCount $highPrivRoleRows.Count -EvidenceSource 'AzureHound' -EvidenceRef (Split-Path $highPrivAppsCsv -Leaf) -Recommendation 'Reduce app permissions to least privilege, remove unused app roles, and prefer scoped/selected resource permissions where possible.' -PolicyRef 'Application permission governance' -Profile $Profile -Tool 'Identity.Security.Assessment.Toolkit'))
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'ENTRA-004' -EvidencePath $highPrivAppsCsv -Domain $tenantName -Notes 'High-privilege app role assignments'
    } else {
        New-EmptyEvidence -Path $highPrivAppsCsv -Headers @('PrincipalDisplayName', 'PrincipalId', 'PrincipalType', 'ResourceDisplayName', 'ResourceId', 'AppRoleId', 'RoleValue', 'RoleDisplayName', 'AssignedDateTime', 'TenantId')
    }
    $evidenceFiles.Add($highPrivAppsCsv)

    # 5) App credentials expiring soon
    $credentialRows = New-Object System.Collections.Generic.List[object]
    $now = [datetime]::UtcNow
    $maxDate = $now.AddDays($CredentialExpiryDays)
    foreach ($app in $apps) {
        $appName = if ($app.displayName) { [string]$app.displayName } else { [string]$app.appId }
        $appId = if ($app.appId) { [string]$app.appId } else { '' }

        $hasPasswordCreds = $app.PSObject.Properties['passwordCredentials'] -and $null -ne $app.passwordCredentials
        if ($hasPasswordCreds) {
            foreach ($secret in @($app.passwordCredentials)) {
                if (-not $secret.endDateTime) { continue }
                $end = $null
                try { $end = [datetime]$secret.endDateTime } catch { $end = $null }
                if (-not $end) { continue }
                if ($end -gt $maxDate) { continue }

                $daysRemaining = [int]([math]::Floor(($end.ToUniversalTime() - $now).TotalDays))
                $credentialRows.Add([pscustomobject]@{
                        AppDisplayName = $appName
                        AppId          = $appId
                        CredentialType = 'Secret'
                        KeyId          = [string]$secret.keyId
                        EndDateUtc     = $end.ToUniversalTime().ToString('u')
                        DaysRemaining  = $daysRemaining
                        IsExpired      = ($daysRemaining -lt 0)
                        TenantId       = $tenantId
                    })
            }
        }

        $hasKeyCreds = $app.PSObject.Properties['keyCredentials'] -and $null -ne $app.keyCredentials
        if ($hasKeyCreds) {
            foreach ($cert in @($app.keyCredentials)) {
                if (-not $cert.endDateTime) { continue }
                $end = $null
                try { $end = [datetime]$cert.endDateTime } catch { $end = $null }
                if (-not $end) { continue }
                if ($end -gt $maxDate) { continue }

                $daysRemaining = [int]([math]::Floor(($end.ToUniversalTime() - $now).TotalDays))
                $credentialRows.Add([pscustomobject]@{
                        AppDisplayName = $appName
                        AppId          = $appId
                        CredentialType = 'Certificate'
                        KeyId          = [string]$cert.keyId
                        EndDateUtc     = $end.ToUniversalTime().ToString('u')
                        DaysRemaining  = $daysRemaining
                        IsExpired      = ($daysRemaining -lt 0)
                        TenantId       = $tenantId
                    })
            }
        }
    }

    $appCredsCsv = Join-Path $entraDir ("azurehound-app-creds-expiring-{0}.csv" -f $SnapshotTimestamp)
    if ($credentialRows.Count -gt 0) {
        $credentialRows | Sort-Object DaysRemaining | Export-Csv -Path $appCredsCsv -NoTypeInformation -Encoding UTF8
        $sev = Get-SeverityFromCount -Count $credentialRows.Count -ThresholdSet (Get-ThresholdSet -Name 'AppCredsExpiring' -Fallback @{ Low = 1; Medium = 3; High = 5 })
        $findings.Add((New-Finding -FindingId 'ENTRA-005' -Category 'Credential Hygiene' -Title "Application credentials expiring within $CredentialExpiryDays days" -Severity $sev -Asset $tenantName -Domain $tenantName -EvidenceCount $credentialRows.Count -EvidenceSource 'AzureHound' -EvidenceRef (Split-Path $appCredsCsv -Leaf) -Recommendation 'Rotate expiring or expired application credentials, migrate to certificates/workload identity where possible, and enforce credential lifetime standards.' -PolicyRef 'Service principal credential management' -Profile $Profile -Tool 'Identity.Security.Assessment.Toolkit'))
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'ENTRA-005' -EvidencePath $appCredsCsv -Domain $tenantName -Notes "Application credentials expiring within $CredentialExpiryDays days"
    } else {
        New-EmptyEvidence -Path $appCredsCsv -Headers @('AppDisplayName', 'AppId', 'CredentialType', 'KeyId', 'EndDateUtc', 'DaysRemaining', 'IsExpired', 'TenantId')
    }
    $evidenceFiles.Add($appCredsCsv)

    # 6) Multi-tenant and public client posture
    $exposureRows = New-Object System.Collections.Generic.List[object]
    foreach ($app in $apps) {
        $redirectUris = @()
        $hasPublicClient = $app.PSObject.Properties['publicClient'] -and $null -ne $app.publicClient
        $publicClientHasRedirects = $hasPublicClient -and $app.publicClient.PSObject.Properties['redirectUris'] -and $null -ne $app.publicClient.redirectUris
        if ($publicClientHasRedirects) {
            $redirectUris = @($app.publicClient.redirectUris)
        }

        $isMultiTenant = ($app.signInAudience -eq 'AzureADMultipleOrgs')
        $isPublicClient = $false
        if ($hasPublicClient -and (@($app.publicClient.PSObject.Properties).Count -gt 0)) {
            $isPublicClient = $true
        }
        $hasLocalhost = @($redirectUris | Where-Object { $_ -match '^https?://localhost' }).Count -gt 0

        if (-not ($isMultiTenant -or $isPublicClient -or $hasLocalhost)) { continue }

        $exposureRows.Add([pscustomobject]@{
                AppDisplayName   = [string]$app.displayName
                AppId            = [string]$app.appId
                SignInAudience   = [string]$app.signInAudience
                IsMultiTenant    = $isMultiTenant
                IsPublicClient   = $isPublicClient
                HasLocalhostUri  = $hasLocalhost
                RedirectUris     = ($redirectUris -join '; ')
                CreatedDateTime  = [string]$app.createdDateTime
                TenantId         = $tenantId
            })
    }

    $appExposureCsv = Join-Path $entraDir ("azurehound-app-exposure-posture-{0}.csv" -f $SnapshotTimestamp)
    if ($exposureRows.Count -gt 0) {
        $exposureRows | Export-Csv -Path $appExposureCsv -NoTypeInformation -Encoding UTF8
        $sev = Get-SeverityFromCount -Count $exposureRows.Count -ThresholdSet (Get-ThresholdSet -Name 'AppExposurePosture' -Fallback @{ Low = 1; Medium = 3; High = 6 })
        $findings.Add((New-Finding -FindingId 'ENTRA-006' -Category 'Application Exposure' -Title 'Multi-tenant/public-client app exposure posture requires review' -Severity $sev -Asset $tenantName -Domain $tenantName -EvidenceCount $exposureRows.Count -EvidenceSource 'AzureHound' -EvidenceRef (Split-Path $appExposureCsv -Leaf) -Recommendation 'Review multi-tenant/public client design, remove unnecessary localhost redirects, and scope sign-in audience to minimum required.' -PolicyRef 'Application registration hardening baseline' -Profile $Profile -Tool 'Identity.Security.Assessment.Toolkit'))
        Add-EvidenceIndex -Index $evidenceIndex -FindingId 'ENTRA-006' -EvidencePath $appExposureCsv -Domain $tenantName -Notes 'Applications with multi-tenant/public-client/localhost exposure indicators'
    } else {
        New-EmptyEvidence -Path $appExposureCsv -Headers @('AppDisplayName', 'AppId', 'SignInAudience', 'IsMultiTenant', 'IsPublicClient', 'HasLocalhostUri', 'RedirectUris', 'CreatedDateTime', 'TenantId')
    }
    $evidenceFiles.Add($appExposureCsv)

    # Optional context dataset for ownerless service principals
    $ownerlessSpCsv = Join-Path $entraDir ("azurehound-ownerless-serviceprincipals-{0}.csv" -f $SnapshotTimestamp)
    $ownerlessSpRows = New-Object System.Collections.Generic.List[object]
    foreach ($spOwner in $servicePrincipalOwners) {
        $ownerCount = if ($spOwner.owners) { @($spOwner.owners).Count } else { 0 }
        if ($ownerCount -gt 0) { continue }
        if (-not $spOwner.servicePrincipalId) { continue }
        $spId = [string]$spOwner.servicePrincipalId
        $sp = $null
        if ($servicePrincipalById.ContainsKey($spId)) { $sp = $servicePrincipalById[$spId] }
        $ownerlessSpRows.Add([pscustomobject]@{
                ServicePrincipalId = $spId
                DisplayName        = if ($sp) { [string]$sp.displayName } else { $null }
                AppId              = if ($sp) { [string]$sp.appId } else { $null }
                ServicePrincipalType = if ($sp) { [string]$sp.servicePrincipalType } else { $null }
                TenantId           = $tenantId
            })
    }
    if ($ownerlessSpRows.Count -gt 0) {
        $ownerlessSpRows | Export-Csv -Path $ownerlessSpCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-EmptyEvidence -Path $ownerlessSpCsv -Headers @('ServicePrincipalId', 'DisplayName', 'AppId', 'ServicePrincipalType', 'TenantId')
    }
    $evidenceFiles.Add($ownerlessSpCsv)

    Export-SATFindings -AssessmentPath $AssessmentPath -Findings $findings -EvidenceIndex $evidenceIndex -Scope 'Entra' | Out-Null

    $findingsArray = @($findings.ToArray())
    $findingIds = @($findingsArray | ForEach-Object { $_.FindingId })
    $evidenceArray = @($evidenceFiles.ToArray())

    Write-SATLog -Message "Invoke-SATAzureHoundAnalysis completed. Findings=$($findings.Count) OutputPath=$AssessmentPath" -LogPath $logPath
    return [pscustomobject]@{
        AssessmentPath = $AssessmentPath
        Scope          = 'Entra'
        EvidenceFiles  = $evidenceArray
        FindingIds     = $findingIds
        Findings       = $findingsArray
    }
}
