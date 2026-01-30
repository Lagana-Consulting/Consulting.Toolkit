function Invoke-ADAssessmentAutomation {
    <#
  .SYNOPSIS
  Automatically generates an AD assessment from Discovery Toolkit output directories.

  .DESCRIPTION
  Discovers AD assessment data from structured discovery output (10_forest/, 20_domains/),
  maps CSV files to appropriate Assessment module table builders, and generates a comprehensive
  Word document following the ADAssessmentMap.json schema.

  .PARAMETER DiscoveryOutputPath
  Root directory path containing discovery output (contains 10_forest/, 20_domains/, 00_schemas/).

  .PARAMETER TemplatePath
  Path to Word template document with bookmarks for sections.

  .PARAMETER OutputPath
  Path where final assessment document will be saved.

  .PARAMETER TableStyleName
  Word table style to apply throughout. If not specified, uses value from config file.
  Falls back to "Light Grid Accent 1" if config value not found.

  .PARAMETER HeaderFontColor
  RGB color for table headers. Default: auto-detected.

  .PARAMETER Visible
  Show Word UI while generating. Default: $false

  .PARAMETER ConfigPath
  Optional override for ADAssessmentMap.json location. Default: module config folder.

  .PARAMETER Sections
  Optional array of section IDs to include. If omitted, all sections processed.

  .EXAMPLE
  Invoke-ADAssessmentAutomation -DiscoveryOutputPath "C:\Discovery\FOREST__20260129-120000" -TemplatePath "C:\Templates\AD_Assessment.dotx" -OutputPath "C:\Reports\Assessment_Final.docx"

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  System.String - Path to generated assessment document.

  .NOTES
  Requires: Discovery Toolkit output with proper structure, ADAssessmentMap.json, Word.Application COM object.
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DiscoveryOutputPath,

        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$TableStyleName,
        [string]$HeaderFontColor,
        [switch]$Visible,
        [string]$ConfigPath,
        [string[]]$Sections
    )

    # Validate input paths
    if (-not (Test-Path $DiscoveryOutputPath)) {
        throw "Discovery output path not found: $DiscoveryOutputPath"
    }

    if (-not (Test-Path $TemplatePath)) {
        throw "Template not found: $TemplatePath"
    }

    # Convert OutputPath to absolute path
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path (Get-Location) $OutputPath
    }

    # Determine config file location
    if (-not $ConfigPath) {
        $configDir = Split-Path -Parent $PSScriptRoot
        $ConfigPath = Join-Path $configDir "config" "ADAssessmentMap.json"
    }

    if (-not (Test-Path $ConfigPath)) {
        throw "ADAssessmentMap.json not found: $ConfigPath"
    }

    # Load configuration
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    # Get styling from config or use defaults
    if (-not $TableStyleName -and $config.Styling) {
        $TableStyleName = $config.Styling.TableStyleName
    }
    if (-not $HeaderFontColor -and $config.Styling) {
        $HeaderFontColor = $config.Styling.DefaultHeaderFontColor
    }
    if (-not $TableStyleName) {
        $TableStyleName = "Light Grid Accent 1"
    }

    # Helper: discover forest-level CSV files
    function Find-ForestCsv {
        param([string]$Pattern, [string]$RootPath)
        $forestPath = Join-Path $RootPath "10_forest"
        if (-not (Test-Path $forestPath)) { return $null }
        $found = @(Get-ChildItem -Path $forestPath -Filter $Pattern -File -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) { return $found[0].FullName }
        return $null
    }

    # Helper: discover domain directories
    function Find-DomainDirectories {
        param([string]$RootPath)
        $domainsPath = Join-Path $RootPath "20_domains"
        if (-not (Test-Path $domainsPath)) { return @() }
        $domains = @(Get-ChildItem -Path $domainsPath -Directory -Filter "Domain-*" | Sort-Object Name)
        return $domains
    }

    # Helper: find domain CSV file
    function Find-DomainCsv {
        param([string]$Pattern, [string]$DomainPath, [string]$DomainName)
        $found = @(Get-ChildItem -Path $DomainPath -Filter $Pattern -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match [regex]::Escape($DomainName) })
        if ($found.Count -gt 0) { return $found[0].FullName }
        return $null
    }

    # Helper: get domain name from directory
    function Get-DomainNameFromPath {
        param([string]$DomainDirName)
        return $DomainDirName -replace '^Domain-', ''
    }

    # Helper: create section context
    function New-SectionContext {
        param([object]$SectionDef, [string]$DomainName = $null)
        $ctx = [ordered]@{
            Id        = $SectionDef.Id
            Title     = $SectionDef.Title
            Bookmark  = if ($SectionDef.Bookmark) { $SectionDef.Bookmark } else { $null }
            Builder   = $SectionDef.Builder
            Mode      = $SectionDef.Mode
            DataFiles = @{}
            Domain    = $DomainName
            Single    = if ($SectionDef.DataSource.Single) { $true } else { $false }
            Columns   = $null
        }
        if ($SectionDef.PSObject.Properties.Name -contains 'Parameters' -and $SectionDef.Parameters) {
            $ctx.Parameters = $SectionDef.Parameters
        }
        if ($SectionDef.PSObject.Properties.Name -contains 'Columns' -and $SectionDef.Columns) {
            $ctx.Columns = $SectionDef.Columns
        }
        return $ctx
    }

    Write-Host "Starting AD Assessment Automation..." -ForegroundColor Cyan
    Write-Host "Discovery Path: $DiscoveryOutputPath" -ForegroundColor Gray

    # Discover section data files
    $sectionContexts = @()
    $domainDirectories = @()

    # Forest-level sections
    foreach ($sectionDef in $config.Sections) {
        if ($Sections -and $Sections -notcontains $sectionDef.Id) { continue }
        $isPerDomain = $sectionDef.DataSource.PSObject.Properties['PerDomain'] -and $sectionDef.DataSource.PerDomain
        if ($isPerDomain) { continue }

        $ctx = New-SectionContext -SectionDef $sectionDef
        if ($sectionDef.DataSource.PSObject.Properties.Name -contains "Pattern") {
            $csvPath = Find-ForestCsv -Pattern $sectionDef.DataSource.Pattern -RootPath $DiscoveryOutputPath
            if ($csvPath) {
                $ctx.DataFiles.CsvPath = $csvPath
                $sectionContexts += $ctx
                Write-Host "  Forest: $($sectionDef.Title)" -ForegroundColor Green
            }
        }
    }

    # Per-domain sections
    $domainDirectories = Find-DomainDirectories -RootPath $DiscoveryOutputPath
    Write-Host "Found $(@($domainDirectories).Count) domain(s)" -ForegroundColor Cyan

    foreach ($domainDir in $domainDirectories) {
        $domainName = Get-DomainNameFromPath -DomainDirName $domainDir.Name
        Write-Host "  Domain: $domainName" -ForegroundColor Gray

        foreach ($sectionDef in $config.Sections) {
            if ($Sections -and $Sections -notcontains $sectionDef.Id) { continue }
            $isPerDomain = $sectionDef.DataSource.PSObject.Properties['PerDomain'] -and $sectionDef.DataSource.PerDomain
            if (-not $isPerDomain) { continue }

            $csvPath = $null
            if ($sectionDef.DataSource.PSObject.Properties.Name -contains "Servers") {
                # Multi-file (Servers + Workstations)
                $serversFile = Find-DomainCsv -Pattern $sectionDef.DataSource.Servers -DomainPath $domainDir.FullName -DomainName $domainName
                $workstationsFile = Find-DomainCsv -Pattern $sectionDef.DataSource.Workstations -DomainPath $domainDir.FullName -DomainName $domainName

                if ($serversFile -and $workstationsFile) {
                    $ctx = New-SectionContext -SectionDef $sectionDef -DomainName $domainName
                    $ctx.DataFiles.Servers = $serversFile
                    $ctx.DataFiles.Workstations = $workstationsFile
                    $sectionContexts += $ctx
                }
            }
            else {
                # Single pattern
                $csvPath = Find-DomainCsv -Pattern $sectionDef.DataSource.Pattern -DomainPath $domainDir.FullName -DomainName $domainName
                if ($csvPath) {
                    $ctx = New-SectionContext -SectionDef $sectionDef -DomainName $domainName
                    $ctx.DataFiles.CsvPath = $csvPath
                    $sectionContexts += $ctx
                }
            }
        }
    }

    Write-Host "Discovered $($sectionContexts.Count) sections" -ForegroundColor Cyan

    # Create Word document
    Write-Host "Creating assessment document..." -ForegroundColor Cyan

    $word = $null
    $doc = $null
    $template = $null

    try {
        $word = New-AdWordInstance -Visible:$Visible

        # Open template READ-ONLY
        $template = $word.Documents.Open($TemplatePath, $false, $true, $false)

        # Create NEW document based on template
        $doc = $word.Documents.Add($template.FullName)

        # Close template
        $template.Close($false)
        Remove-AdComObject -ComObject $template
        $template = $null

        # Add sections to document
        $successCount = 0
        $failureCount = 0

        foreach ($ctx in $sectionContexts) {
            Write-Host "  Section: $($ctx.Title)" -ForegroundColor Cyan

            try {
                # Get bookmark range if available
                $insertRange = $null
                if ($ctx.Bookmark) {
                    $insertRange = Get-AdBookmarkRange -Document $doc -BookmarkName $ctx.Bookmark
                    if (-not $insertRange) {
                        Write-Warning "Bookmark not found: $($ctx.Bookmark)"
                        $failureCount++
                        continue
                    }
                }

                # Build parameters
                $builderFunc = $ctx.Builder
                $builderParams = @{
                    Document       = $doc
                    Title          = $ctx.Title
                    TableStyleName = $TableStyleName
                }

                if ($HeaderFontColor) {
                    $builderParams.HeaderFontColor = $HeaderFontColor
                }

                if ($insertRange) {
                    $builderParams.InsertRange = $insertRange
                }

                # Multi-file builders
                if ($ctx.DataFiles.ContainsKey("Servers")) {
                    $builderParams.ServersCsvPath = $ctx.DataFiles.Servers
                    $builderParams.WorkstationsCsvPath = $ctx.DataFiles.Workstations
                    if ($ctx.Parameters) {
                        foreach ($pkey in $ctx.Parameters.Keys) {
                            $builderParams[$pkey] = $ctx.Parameters[$pkey]
                        }
                    }
                }
                else {
                    # Single-file builders
                    $builderParams.CsvPath = $ctx.DataFiles.CsvPath
                }

                # Add Columns if present
                if ($ctx.Columns) {
                    $builderParams.Columns = $ctx.Columns
                }

                # Call builder function
                if (Get-Command $builderFunc -ErrorAction SilentlyContinue) {
                    & $builderFunc @builderParams 2>$null | Out-Null
                    $successCount++
                    Write-Host "    Added OK" -ForegroundColor Green
                }
                else {
                    Write-Warning "Builder not found: $builderFunc"
                    $failureCount++
                }
            }
            catch {
                Write-Warning "Error: $($_.Exception.Message)"
                $failureCount++
            }
        }

        # Save document
        $OutputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        $doc.SaveAs($OutputPath, 16)
        Write-Host "`nDocument saved: $OutputPath" -ForegroundColor Green
        Write-Host "Results: $successCount success, $failureCount failed" -ForegroundColor Cyan

        return $OutputPath
    }
    finally {
        if ($template) { $template.Close($false) | Out-Null }
        if ($doc) { $doc.Close($false) | Out-Null }
        if ($word) { $word.Quit() | Out-Null }

        if ($template) { Remove-AdComObject -ComObject $template }
        if ($doc) { Remove-AdComObject -ComObject $doc }
        if ($word) { Remove-AdComObject -ComObject $word }

        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}
