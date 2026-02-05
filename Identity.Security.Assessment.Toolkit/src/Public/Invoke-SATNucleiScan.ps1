function Invoke-SATNucleiAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RawJsonlPath,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'LowImpact',

        [string]$AssessmentPath,
        [string]$OutputRoot,
        [string]$SnapshotTimestamp,
        [string]$ConfigRoot
    )

    Set-StrictMode -Version Latest

    if (-not (Test-Path $RawJsonlPath)) {
        throw "RawJsonlPath not found: $RawJsonlPath"
    }

    if (-not $AssessmentPath) {
        $AssessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
    }

    if (-not $SnapshotTimestamp) {
        $SnapshotTimestamp = (Get-Date -Format 'yyyyMMddHHmmss')
    }

    $logsDir = Join-Path $AssessmentPath 'Logs'
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $logPath = Join-Path $logsDir 'RunLog.txt'
    Write-SATLog -Message "Invoke-SATNucleiAnalysis started. Profile=$Profile" -LogPath $logPath

    $evidenceRoot = Join-Path $AssessmentPath 'Evidence'
    $nucleiDir = Join-Path $evidenceRoot 'Nuclei'
    if (-not (Test-Path $nucleiDir)) { New-Item -ItemType Directory -Path $nucleiDir -Force | Out-Null }

    $normalizedCsv = Join-Path $nucleiDir ("nuclei-normalized-{0}.csv" -f $SnapshotTimestamp)

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    if (-not $ConfigRoot) {
        $ConfigRoot = Join-Path $moduleRoot 'config'
    }

    $severityMapPath = Join-Path $ConfigRoot 'severity_map.json'
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

    # -----------------------------
    # Identity-focused mapping layer
    # -----------------------------

    function ConvertTo-TagList {
        param([object]$TagsValue)

        if ($null -eq $TagsValue) { return @() }

        # In Nuclei JSONL, info.tags is often a comma-separated string; sometimes array-like.
        if ($TagsValue -is [string]) {
            return @($TagsValue.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
        }

        if ($TagsValue -is [System.Collections.IEnumerable]) {
            $out = @()
            foreach ($t in $TagsValue) {
                if ($t) { $out += ($t.ToString().Trim().ToLowerInvariant()) }
            }
            return @($out | Where-Object { $_ })
        }

        return @()
    }

    function Get-Stable3DigitCode {
        param([Parameter(Mandatory)][string]$Key)

        # Deterministic across runs: SHA1(Key) -> first 2 bytes -> 0..999 -> 001..999
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Key)
        $sha1 = [System.Security.Cryptography.SHA1]::Create()
        $hash = $sha1.ComputeHash($bytes)

        $num = ([int]$hash[0] * 256) + [int]$hash[1]
        $code = ($num % 999) + 1
        return ('{0:d3}' -f $code)
    }

    function Get-IdentityBucket {
        param(
            [string]$TemplateId,
            [string]$TemplatePath,
            [string]$Name,
            [string[]]$Tags
        )

        $tid = if ($TemplateId) { $TemplateId.ToLowerInvariant() } else { '' }
        $tpath = if ($TemplatePath) { $TemplatePath.ToLowerInvariant() } else { '' }
        $nm = if ($Name) { $Name.ToLowerInvariant() } else { '' }
        $tags = @($Tags | ForEach-Object { $_.ToLowerInvariant() })

        function HasAny {
            param([string[]]$Needles)
            foreach ($n in $Needles) {
                if ($tags -contains $n) { return $true }
            }
            return $false
        }

        # AD CS / Certificates
        if (HasAny @('adcs', 'cert', 'certificate', 'certificates') -or
            ($tpath -match 'windows/adcs' -or $tpath -match 'windows/certificates') -or
            ($tid -match 'adcs|certsrv|certificat') -or
            ($nm -match 'adcs|certsrv|certificate')) {
            return 'ADCS'
        }

        # Kerberos
        if (HasAny @('kerberos', 'krb', 'kdc') -or
            ($tpath -match 'kerberos') -or
            ($tid -match 'kerberos|krb') -or
            ($nm -match 'kerberos')) {
            return 'KRB'
        }

        # LDAP / LDAPS
        if (HasAny @('ldap', 'ldaps') -or
            ($tpath -match 'ldap') -or
            ($tid -match 'ldap|ldaps') -or
            ($nm -match 'ldap|ldaps')) {
            return 'LDAP'
        }

        # NTLM / relay-related auth exposure
        if (HasAny @('ntlm', 'relay') -or
            ($tpath -match 'ntlm') -or
            ($tid -match 'ntlm') -or
            ($nm -match 'ntlm')) {
            return 'NTLM'
        }

        # SMB
        if (HasAny @('smb') -or
            ($tpath -match 'smb') -or
            ($tid -match 'smb') -or
            ($nm -match 'smb')) {
            return 'SMB'
        }

        # ADFS / federation
        if (HasAny @('adfs', 'federation') -or
            ($tpath -match 'adfs') -or
            ($tid -match 'adfs') -or
            ($nm -match 'adfs|federation')) {
            return 'ADFS'
        }

        # Azure / Entra / cloud identity endpoints
        if (HasAny @('azure', 'entra', 'microsoft', 'o365', 'm365') -or
            ($tpath -match 'cloud/azure|exposures/azure') -or
            ($tid -match 'azure|entra|o365|m365') -or
            ($nm -match 'azure|entra|microsoft 365|office 365')) {
            return 'AZURE'
        }

        return 'GEN'
    }

    function Get-IdentityMetadata {
        param([string]$Bucket)

        switch ($Bucket) {
            'ADCS' {
                return @{
                    Category       = 'Identity'
                    TitlePrefix    = 'AD CS / Certificates'
                    Recommendation = 'Review AD CS exposure and certificate template security. Restrict enrollment, require manager approval where appropriate, and harden CA/CertSrv endpoints. Validate for ESC-style misconfigurations and remove risky templates.'
                    PolicyRef      = 'Microsoft AD CS hardening; Tier 0 / PKI controls'
                }
            }
            'KRB' {
                return @{
                    Category       = 'Identity'
                    TitlePrefix    = 'Kerberos'
                    Recommendation = 'Validate Kerberos exposure and configuration. Reduce legacy authentication paths, enforce modern crypto where possible, and review for known Kerberos-related weaknesses impacting authentication.'
                    PolicyRef      = 'Kerberos hardening guidance; CIS AD controls'
                }
            }
            'LDAP' {
                return @{
                    Category       = 'Identity'
                    TitlePrefix    = 'LDAP / LDAPS'
                    Recommendation = 'Validate LDAP/LDAPS configuration. Enforce LDAP signing and channel binding where applicable, reduce anonymous binds, and ensure LDAP is not exposed beyond trusted network boundaries.'
                    PolicyRef      = 'LDAP signing/channel binding; CIS AD controls'
                }
            }
            'NTLM' {
                return @{
                    Category       = 'Identity'
                    TitlePrefix    = 'NTLM'
                    Recommendation = 'Reduce NTLM usage and exposure. Prefer Kerberos, enforce SMB signing where required, and review services that enable credential relay paths. Apply NTLM auditing and phase-out plan.'
                    PolicyRef      = 'NTLM reduction guidance; Microsoft identity hardening'
                }
            }
            'SMB' {
                return @{
                    Category       = 'Identity'
                    TitlePrefix    = 'SMB'
                    Recommendation = 'Review SMB configuration related to authentication and relay risk. Enforce SMB signing where appropriate, disable legacy SMB versions, and validate access boundaries for admin services.'
                    PolicyRef      = 'SMB hardening; CIS Windows Server controls'
                }
            }
            'ADFS' {
                return @{
                    Category       = 'Identity'
                    TitlePrefix    = 'ADFS / Federation'
                    Recommendation = 'Review federation endpoints and patch level. Validate ADFS configuration, ensure strong TLS, and confirm the service is appropriately isolated and monitored due to its role in token issuance.'
                    PolicyRef      = 'Federation service hardening; hybrid identity controls'
                }
            }
            'AZURE' {
                return @{
                    Category       = 'Identity'
                    TitlePrefix    = 'Azure / Entra'
                    Recommendation = 'Validate exposure of hybrid/cloud identity endpoints and configuration signals. Confirm administrative endpoints and metadata are intended to be public, and ensure tenant identity hardening is applied.'
                    PolicyRef      = 'Microsoft Entra ID security best practices'
                }
            }
            default {
                return @{
                    Category       = 'Vulnerability'
                    TitlePrefix    = 'Nuclei'
                    Recommendation = 'Validate the finding, confirm exposure, and remediate per vendor guidance/change control.'
                    PolicyRef      = 'Client vulnerability management policy'
                }
            }
        }
    }

    function Get-StableFindingId {
        param(
            [string]$Bucket,
            [string]$TemplateId
        )

        $key = if ($TemplateId) { $TemplateId } else { 'unknown-template' }
        $code = Get-Stable3DigitCode -Key ("{0}:{1}" -f $Bucket, $key)
        if ($Bucket -and $Bucket -ne 'GEN') {
            return ("NUC-{0}-{1}" -f $Bucket, $code)
        }
        return ("NUC-GEN-{0}" -f $code)
    }

    # Parse JSONL
    $rows = New-Object System.Collections.Generic.List[object]
    Get-Content -Path $RawJsonlPath -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if (-not $line) { return }
        try {
            $o = $line | ConvertFrom-Json

            $templateId = $null
            if ($o.PSObject.Properties['template-id']) { $templateId = $o.'template-id' }
            elseif ($o.PSObject.Properties['templateID']) { $templateId = $o.templateID }

            # Some outputs include template path/name fields; keep best-effort.
            $templatePath = $null
            if ($o.PSObject.Properties['template-path']) { $templatePath = $o.'template-path' }
            elseif ($o.PSObject.Properties['template']) { $templatePath = $o.template }

            $severity = $null
            $tagsValue = $null
            $name = $null
            $reference = $null

            if ($o.PSObject.Properties['info']) {
                if ($o.info.PSObject.Properties['severity']) { $severity = [string]$o.info.severity }
                if ($o.info.PSObject.Properties['tags']) { $tagsValue = $o.info.tags }
                if ($o.info.PSObject.Properties['name']) { $name = [string]$o.info.name }
                if ($o.info.PSObject.Properties['reference']) { $reference = $o.info.reference }
            }

            $tags = ConvertTo-TagList -TagsValue $tagsValue

            $rows.Add([pscustomobject]@{
                    TemplateId   = [string]$templateId
                    TemplatePath = [string]$templatePath
                    Name         = $name
                    SeverityRaw  = $severity
                    Host         = if ($o.host) { [string]$o.host } else { $null }
                    MatchedAt    = if ($o.'matched-at') { [string]$o.'matched-at' } else { $null }
                    Type         = if ($o.type) { [string]$o.type } else { $null }
                    Matcher      = if ($o.matcher) { [string]$o.matcher } else { $null }
                    Extracted    = if ($o.extracted_results) { ($o.extracted_results -join '; ') } else { $null }
                    Timestamp    = if ($o.timestamp) { [string]$o.timestamp } else { $null }
                    Reference    = if ($reference) {
                        if ($reference -is [string]) { $reference }
                        elseif ($reference -is [System.Collections.IEnumerable]) { ($reference -join '; ') }
                        else { $reference.ToString() }
                    } else { $null }
                    Tags         = ($tags -join ',')
                    TagsList     = $tags
                })
        } catch {
            # ignore malformed lines; keep it resilient
        }
    }

    if ($rows.Count -gt 0) {
        $rows | Export-Csv -Path $normalizedCsv -NoTypeInformation -Encoding UTF8
    } else {
        @() | Export-Csv -Path $normalizedCsv -NoTypeInformation -Encoding UTF8
    }

    # Convert to SAT findings: group by TemplateId (and implicitly by identity bucket)
    $severityMapText = @{
        'info'     = 'Informational'
        'low'      = 'Low'
        'medium'   = 'Medium'
        'high'     = 'High'
        'critical' = 'Critical'
    }

    $findings = New-Object System.Collections.Generic.List[object]
    $evidenceIndex = New-Object System.Collections.Generic.List[object]

    Add-EvidenceIndex -Index $evidenceIndex `
        -FindingId 'NUCLEI-INDEX' `
        -EvidencePath $normalizedCsv `
        -Domain 'All' `
        -Notes 'Normalized Nuclei results (identity-focused grouping and stable IDs)'

    $grouped = $rows | Group-Object -Property TemplateId
    foreach ($g in $grouped) {
        if (-not $g.Name) { continue }

        $sample = $g.Group | Select-Object -First 1

        $sevKey = if ($sample.SeverityRaw) { $sample.SeverityRaw.ToLowerInvariant() } else { 'info' }
        $sev = if ($severityMapText.ContainsKey($sevKey)) { $severityMapText[$sevKey] } else { 'Informational' }

        $bucket = Get-IdentityBucket -TemplateId $sample.TemplateId -TemplatePath $sample.TemplatePath -Name $sample.Name -Tags $sample.TagsList
        $meta = Get-IdentityMetadata -Bucket $bucket

        $stableId = Get-StableFindingId -Bucket $bucket -TemplateId $sample.TemplateId

        $baseTitle = if ($sample.Name) { $sample.Name } else { "Nuclei finding: $($g.Name)" }
        $title = if ($bucket -and $bucket -ne 'GEN') {
            "{0}: {1}" -f $meta.TitlePrefix, $baseTitle
        } else {
            $baseTitle
        }

        $asset = if ($sample.Host) { [string]$sample.Host } else { 'Targets' }

        $findings.Add((
                New-Finding -FindingId $stableId `
                    -Category $meta.Category `
                    -Title $title `
                    -Severity $sev `
                    -Asset $asset `
                    -Domain 'All' `
                    -EvidenceCount ([int]$g.Count) `
                    -EvidenceSource 'Nuclei' `
                    -EvidenceRef (Split-Path $normalizedCsv -Leaf) `
                    -Recommendation $meta.Recommendation `
                    -PolicyRef $meta.PolicyRef `
                    -Profile $Profile `
                    -Tool 'Identity.Security.Assessment.Toolkit'
            ))
    }

    Export-SATFindings -AssessmentPath $AssessmentPath -Findings $findings -EvidenceIndex $evidenceIndex -Scope 'Nuclei' | Out-Null

    Write-SATLog -Message "Invoke-SATNucleiAnalysis completed. OutputPath=$AssessmentPath" -LogPath $logPath
    return [pscustomobject]@{
        AssessmentPath = $AssessmentPath
        Scope          = 'Nuclei'
        EvidenceFiles  = @($normalizedCsv)
        FindingIds     = @($findings | Select-Object -ExpandProperty FindingId)
        Findings       = @($findings)
    }
}
