function Invoke-SATSharpHoundCollection {
    <#
    .SYNOPSIS
      Runs SharpHound.ps1 collection and normalizes output to SAT BloodHound analysis naming/layout.

    .DESCRIPTION
      - Dot-sources SharpHound.ps1 and calls Invoke-BloodHound.
      - Uses profile gating (LowImpact / Standard / Deep) to choose safe collection methods.
      - Produces timestamp-prefixed JSON files in:
          <AssessmentPath>\Evidence\BloodHound\<timestamp>_<type>.json
      - Preserves original zip in:
          <AssessmentPath>\Evidence\BloodHound\Raw\<timestamp>_sharphound.zip
      - Writes RunMetadata.json capturing options + tool details.

    .PARAMETER SharpHoundPath
      Path to SharpHound.ps1.

    .PARAMETER Profile
      LowImpact | Standard | Deep

    .PARAMETER OutputRoot
      Base output folder. If provided, a timestamped assessment folder is created within.

    .PARAMETER AssessmentPath
      Optional. Use an existing assessment folder (preferred if you already created one with the toolkit).

    .PARAMETER Domain
      Optional. AD domain FQDN. If omitted, SharpHound will use current domain context.

    .PARAMETER DomainController
      Optional. Explicit domain controller to target.

    .PARAMETER CollectionMethod
      Optional. Overrides profile defaults (e.g. "Group,ACL,ObjectProps").

    .PARAMETER Stealth
      Optional. Force stealth mode. Defaults to ON for LowImpact/Standard.

    .PARAMETER Throttle
      Optional. SharpHound throttle.

    .PARAMETER Jitter
      Optional. SharpHound jitter.

    .PARAMETER NoZip
      Optional. Do not create a zip. (Not recommended; analysis prefers consistent snapshot packaging.)

    .PARAMETER KeepTemp
      Optional. Keep temporary extraction folder for debugging.

    .EXAMPLE
      Invoke-SATSharpHoundCollection -SharpHoundPath .\tools\SharpHound.ps1 -Profile LowImpact

    .EXAMPLE
      Invoke-SATSharpHoundCollection -SharpHoundPath .\tools\SharpHound.ps1 -Profile Deep -Domain contoso.local -DomainController dc1.contoso.local
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SharpHoundPath,

        [ValidateSet('LowImpact', 'Standard', 'Deep')]
        [string]$Profile = 'Standard',

        [string]$OutputRoot,

        [string]$AssessmentPath,

        [string]$Domain,

        [string]$DomainController,

        [string]$CollectionMethod,

        [switch]$Stealth,

        [ValidateRange(1, 50)]
        [int]$Throttle = 10,

        [ValidateRange(0, 100)]
        [int]$Jitter = 20,

        [switch]$NoZip,

        [switch]$KeepTemp
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function New-Directory {
        param([Parameter(Mandatory)][string]$Path)
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path | Out-Null
        }
    }

    function Get-NowStamp {
        # yyyyMMddHHmmss (matches your analysis expectations)
        (Get-Date).ToString('yyyyMMddHHmmss')
    }

    function Write-Log {
        param(
            [Parameter(Mandatory)][string]$Message,
            [ValidateSet('INFO', 'WARN', 'ERROR')]
            [string]$Level = 'INFO'
        )
        $line = "[{0}] [{1}] {2}" -f (Get-Date).ToString('s'), $Level, $Message
        Write-Host $line
        if ($script:LogPath) {
            Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
        }
    }

    function Get-ProfileCollectionMethods {
        param([string]$ProfileName)

        # These are intentionally conservative defaults.
        # - LowImpact: directory-only, avoids endpoint/session style enumeration
        # - Standard: still mostly directory, adds Trusts (useful, low noise)
        # - Deep: adds endpoint/session-related methods (higher friction/noise)
        switch ($ProfileName) {
            'LowImpact' {
                # Safe, high-signal for identity posture
                return 'Group,ACL,ObjectProps,Container'
            }
            'Standard' {
                return 'Group,ACL,ObjectProps,Container,Trusts'
            }
            'Deep' {
                # Adds higher-friction methods; clients may restrict these.
                return 'Group,ACL,ObjectProps,Container,Trusts,LocalAdmin,Session,LoggedOn,RDP,DCOM,PSRemote'
            }
            default {
                return 'Group,ACL,ObjectProps,Container,Trusts'
            }
        }
    }

    # ----------------------------
    # Resolve paths / output layout
    # ----------------------------
    if (-not (Test-Path $SharpHoundPath)) {
        throw "SharpHound.ps1 not found: $SharpHoundPath"
    }

    $timestamp = Get-NowStamp

    if (-not $AssessmentPath) {
        if (Get-Command -Name New-SATOutputFolder -ErrorAction SilentlyContinue) {
            $AssessmentPath = New-SATOutputFolder -OutputRoot $OutputRoot
        } else {
            if (-not $OutputRoot) {
                $OutputRoot = Join-Path (Get-Location) 'output'
            }
            New-Directory $OutputRoot
            $AssessmentPath = Join-Path $OutputRoot ("SAT_{0}" -f $timestamp)
            New-Directory $AssessmentPath
        }
    }

    $evidenceRoot = Join-Path $AssessmentPath 'Evidence\BloodHound'
    $rawRoot = Join-Path $evidenceRoot 'Raw'
    $tempRoot = Join-Path $evidenceRoot ("_tmp_extract_{0}" -f $timestamp)
    $script:LogPath = Join-Path $AssessmentPath 'Logs\RunLog.txt'

    New-Directory $AssessmentPath
    New-Directory (Join-Path $AssessmentPath 'Logs')
    New-Directory $evidenceRoot
    New-Directory $rawRoot

    Write-Log "AssessmentPath: $AssessmentPath"
    Write-Log "EvidenceRoot: $evidenceRoot"
    Write-Log "Profile: $Profile"

    # ----------------------------
    # Determine collection methods
    # ----------------------------
    if (-not $CollectionMethod) {
        $CollectionMethod = Get-ProfileCollectionMethods -ProfileName $Profile
    }

    # Default stealth behavior: ON for LowImpact/Standard, OFF for Deep unless explicitly requested.
    $useStealth = $false
    if ($Stealth.IsPresent) {
        $useStealth = $true
    } elseif ($Profile -in @('LowImpact', 'Standard')) {
        $useStealth = $true
    }

    Write-Log "CollectionMethod: $CollectionMethod"
    Write-Log ("Stealth: {0}; Throttle: {1}; Jitter: {2}; Zip: {3}" -f $useStealth, $Throttle, $Jitter, (-not $NoZip.IsPresent))

    # ----------------------------
    # Load SharpHound.ps1 and validate Invoke-BloodHound
    # ----------------------------
    Write-Log "Dot-sourcing SharpHound script: $SharpHoundPath"
    . $SharpHoundPath

    $invoke = Get-Command -Name Invoke-BloodHound -ErrorAction SilentlyContinue
    if (-not $invoke) {
        throw "Invoke-BloodHound was not found after dot-sourcing $SharpHoundPath. Verify this is a compatible SharpHound.ps1."
    }

    # Identify SharpHound version if available (best effort)
    $shVersion = $null
    try {
        # Some releases expose a script-scoped or global variable, others don't.
        if (Get-Variable -Name SharpHoundVersion -Scope Global -ErrorAction SilentlyContinue) {
            $shVersion = (Get-Variable -Name SharpHoundVersion -Scope Global).Value
        }
    } catch { }

    # ----------------------------
    # Run collection to a staging folder (SharpHound output directory)
    # ----------------------------
    $stageOut = Join-Path $evidenceRoot ("_stage_{0}" -f $timestamp)
    New-Directory $stageOut

    # Prefer a deterministic zip name when supported.
    # Invoke-BloodHound supports various parameters depending on version. We'll splat safely.
    $zipName = "{0}_sharphound.zip" -f $timestamp

    $splat = @{
        OutputDirectory  = $stageOut
        CollectionMethod = $CollectionMethod
        Throttle         = $Throttle
        Jitter           = $Jitter
    }
    if ($useStealth) { $splat['Stealth'] = $true }

    if ($Domain) { $splat['Domain'] = $Domain }
    if ($DomainController) { $splat['DomainController'] = $DomainController }

    # Zip controls are version dependent; attempt best effort.
    if (-not $NoZip.IsPresent) {
        $splat['ZipFileName'] = $zipName
    } else {
        # Some versions use -NoZip switch; try it if present.
        if ($invoke.Parameters.ContainsKey('NoZip')) {
            $splat['NoZip'] = $true
        }
    }

    Write-Log "Starting SharpHound collection..."
    try {
        Invoke-BloodHound @splat | Out-Null
        Write-Log "SharpHound collection completed."
    } catch {
        Write-Log ("SharpHound collection failed: {0}" -f $_.Exception.Message) 'ERROR'
        throw
    }

    # ----------------------------
    # Locate the zip (or JSON files) produced by SharpHound
    # ----------------------------
    $zipPath = $null
    if (-not $NoZip.IsPresent) {
        $candidate = Join-Path $stageOut $zipName
        if (Test-Path $candidate) {
            $zipPath = $candidate
        } else {
            # Fallback: newest zip in stageOut
            $zipPath = Get-ChildItem -Path $stageOut -Filter *.zip -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 |
            ForEach-Object { $_.FullName }
        }

        if (-not $zipPath) {
            throw "Expected zip output but no zip was found in: $stageOut"
        }

        # Preserve raw zip in deterministic location/name
        $rawZip = Join-Path $rawRoot ("{0}_sharphound.zip" -f $timestamp)
        Copy-Item -Path $zipPath -Destination $rawZip -Force
        Write-Log "Saved raw zip: $rawZip"
    }

    # ----------------------------
    # Normalize JSON output to <timestamp>_<type>.json in Evidence\BloodHound
    # ----------------------------
    # Your analysis expects files like: 20260201123456_users.json, 20260201123456_computers.json, etc.
    # We'll extract zip (preferred) and rename each JSON accordingly.
    New-Directory $tempRoot

    if ($zipPath) {
        Write-Log "Extracting zip to temp: $tempRoot"
        Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force
    } else {
        # NoZip mode: treat stageOut as already containing JSONs
        Write-Log "NoZip mode: using stage folder as input: $stageOut" 'WARN'
        Copy-Item -Path (Join-Path $stageOut '*.json') -Destination $tempRoot -Force -ErrorAction SilentlyContinue
    }

    $jsonFiles = Get-ChildItem -Path $tempRoot -Filter *.json -File -ErrorAction SilentlyContinue
    if (-not $jsonFiles -or $jsonFiles.Count -eq 0) {
        throw "No JSON files found after extraction/copy. TempRoot: $tempRoot"
    }

    $normalized = New-Object System.Collections.Generic.List[object]

    foreach ($jf in $jsonFiles) {
        # Typical filenames: users.json, computers.json, groups.json, domains.json, ous.json, gpos.json, containers.json, sessions.json, localgroups.json, etc.
        # We'll normalize to <timestamp>_<basename>.json
        $base = [IO.Path]::GetFileNameWithoutExtension($jf.Name)

        # Defensive: if the file name already contains a leading timestamp, strip it.
        $base = $base -replace '^\d{14}_', ''

        $destName = "{0}_{1}.json" -f $timestamp, $base
        $destPath = Join-Path $evidenceRoot $destName

        Copy-Item -Path $jf.FullName -Destination $destPath -Force

        $normalized.Add([pscustomobject]@{
                SourceFile = $jf.Name
                OutputFile = $destName
                Bytes      = $jf.Length
            })

        Write-Log "Normalized: $($jf.Name) -> $destName"
    }

    # ----------------------------
    # Write RunMetadata.json
    # ----------------------------
    $metaPath = Join-Path $evidenceRoot ("{0}_RunMetadata.json" -f $timestamp)

    $meta = [ordered]@{
        Timestamp         = $timestamp
        Profile           = $Profile
        Domain            = $Domain
        DomainController  = $DomainController
        CollectionMethod  = $CollectionMethod
        Stealth           = $useStealth
        Throttle          = $Throttle
        Jitter            = $Jitter
        ZipEnabled        = (-not $NoZip.IsPresent)
        RawZipSaved       = (Test-Path (Join-Path $rawRoot ("{0}_sharphound.zip" -f $timestamp)))
        SharpHoundPath    = $SharpHoundPath
        SharpHoundVersion = $shVersion
        AssessmentPath    = $AssessmentPath
        OutputRoot        = $OutputRoot
        EvidenceRoot      = $evidenceRoot
        NormalizedFiles   = $normalized
        CollectedAtUtc    = (Get-Date).ToUniversalTime().ToString('o')
    }

    ($meta | ConvertTo-Json -Depth 6) | Set-Content -Path $metaPath -Encoding UTF8
    Write-Log "Wrote metadata: $metaPath"

    # ----------------------------
    # Cleanup temp
    # ----------------------------
    if (-not $KeepTemp.IsPresent) {
        try {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction Stop
            Remove-Item -Path $stageOut -Recurse -Force -ErrorAction Stop
            Write-Log "Cleaned temp folders."
        } catch {
            Write-Log ("Failed to clean temp folders: {0}" -f $_.Exception.Message) 'WARN'
        }
    } else {
        Write-Log "KeepTemp specified; leaving temp folders for inspection: $tempRoot"
    }

    Write-Log "SharpHound collection + normalization complete."

    # Emit a small summary object
    [pscustomobject]@{
        Timestamp      = $timestamp
        AssessmentPath = $AssessmentPath
        OutputRoot     = $OutputRoot
        EvidenceRoot   = $evidenceRoot
        RawZip         = (Join-Path $rawRoot ("{0}_sharphound.zip" -f $timestamp))
        Metadata       = $metaPath
        FilesWritten   = $normalized.Count
        Scope          = 'BloodHoundCollection'
        EvidenceFiles  = @($normalized | ForEach-Object { Join-Path $evidenceRoot $_.OutputFile })
        FindingIds     = @()
    }
}
