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
  Word table style to apply throughout. Default: "Light Grid Accent 1"

  .PARAMETER HeaderFontColor
  RGB color for table headers. Default: auto-detected.

  .PARAMETER Visible
  Show Word UI while generating. Default: $false

  .PARAMETER ConfigPath
  Optional override for ADAssessmentMap.json location. Default: module config folder.

  .PARAMETER Sections
  Optional array of section IDs to include. If omitted, all sections processed.

  .EXAMPLE
  Invoke-ADAssessmentAutomation -DiscoveryOutputPath "C:\Discovery\FOREST__20260129-120000" `
    -TemplatePath "C:\Templates\AD_Assessment.dotx" `
    -OutputPath "C:\Reports\Assessment_Final.docx"

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  System.String - Path to generated assessment document.

  .NOTES
  Requires:
  - Discovery Toolkit output with 10_forest/, 20_domains/, 00_schemas/ structure
  - ADAssessmentMap.json configuration file
  - Word.Application COM object
  - Migration.Toolkit.Assessment module functions

  Discovery output structure:
    Root/
      10_forest/          - Forest-level CSVs (trusts, sites, subnets, UPN suffixes)
      20_domains/         - Per-domain directories with domain-specific CSVs
        Domain-name.com/  - Users, Computers, Groups, GPOs, Policies, OUs, etc.
      00_schemas/         - Column definition CSVs for validation
      99_manifest/        - Execution metadata

  .LINK
  Invoke-ADOnlyAssessment
  Invoke-FullAssessment
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DiscoveryOutputPath,

        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [string]$TableStyleName = "Light Grid Accent 1",
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

    # Convert OutputPath to absolute path (Word COM requires absolute paths)
    $OutputPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputPath))

    # Determine config file location
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot ".." "config" "ADAssessmentMap.json"
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
        param(
            [string]$Pattern,
            [string]$RootPath
        )
        $forestPath = Join-Path $RootPath "10_forest"
        if (-not (Test-Path $forestPath)) { return $null }

        $found = Get-ChildItem -Path $forestPath -Filter $Pattern -File -ErrorAction SilentlyContinue
        if ($found) { return $found[0].FullName } else { return $null }
    }

    # Helper: discover domain directories
    function Find-DomainDirectories {
        param([string]$RootPath)

        $domainsPath = Join-Path $RootPath "20_domains"
        if (-not (Test-Path $domainsPath)) { return @() }

        $domains = Get-ChildItem -Path $domainsPath -Directory -Filter "Domain-*" |
        Sort-Object Name

        return $domains
    }

    # Helper: find domain CSV file with flexible pattern matching
    function Find-DomainCsv {
        param(
            [string]$Pattern,
            [string]$DomainPath,
            [string]$DomainName
        )

        $found = Get-ChildItem -Path $DomainPath -Filter $Pattern -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match [regex]::Escape($DomainName) } |
        Select-Object -First 1

        if ($found) { return $found.FullName } else { return $null }
    }

    # Helper: normalize domain name from directory
    function Get-DomainNameFromPath {
        param([string]$DomainDirName)
        # "Domain-sourcelab.com" -> "sourcelab.com"
        return $DomainDirName -replace '^Domain-', ''
    }

    # Helper: create section context
    function New-SectionContext {
        param(
            [object]$SectionDef,
            [string]$DomainName = $null
        )

        $ctx = [ordered]@{
            Id        = $SectionDef.Id
            Title     = $SectionDef.Title
            Bookmark  = if ($SectionDef.Bookmark) { $SectionDef.Bookmark } else { $null }
            Builder   = $SectionDef.Builder
            Mode      = $SectionDef.Mode
            DataFiles = @{}
            Domain    = $DomainName
        }

        if ($SectionDef.DataSource.Single) {
            $ctx.Single = $true
        }
        else {
            $ctx.Single = $false
        }

        if ($SectionDef.PSObject.Properties['Parameters'] -and $SectionDef.Parameters) {
            $ctx.Parameters = $SectionDef.Parameters
        }

        return $ctx
    }

    Write-Host "Starting AD Assessment Automation..." -ForegroundColor Cyan
    Write-Host "Discovery Path: $DiscoveryOutputPath" -ForegroundColor Gray
    Write-Host "Template: $TemplatePath" -ForegroundColor Gray

    # Discover data files
    $sectionContexts = @()
    $domainDirectories = @()

    foreach ($sectionDef in $config.Sections) {
        # Skip if specific sections requested and this isn't one
        if ($Sections -and $Sections -notcontains $sectionDef.Id) { continue }

        # Skip per-domain sections (handled separately below)
        $isPerDomain = $sectionDef.DataSource.PSObject.Properties['PerDomain'] -and $sectionDef.DataSource.PerDomain
        if ($isPerDomain) { continue }

        $ctx = New-SectionContext -SectionDef $sectionDef

        # Forest-level section
        if ($sectionDef.DataSource.PSObject.Properties.Name -contains "Pattern") {
            $csvPath = Find-ForestCsv -Pattern $sectionDef.DataSource.Pattern -RootPath $DiscoveryOutputPath
            if ($csvPath) {
                $ctx.DataFiles.CsvPath = $csvPath
                $sectionContexts += $ctx
                Write-Host "  Found: $($sectionDef.Title) -> $(Split-Path $csvPath -Leaf)" -ForegroundColor Green
            }
            else {
                Write-Warning "CSV not found for section: $($sectionDef.Id) (Pattern: $($sectionDef.DataSource.Pattern))"
            }
        }
    }

    # Per-domain sections
    $domainDirectories = Find-DomainDirectories -RootPath $DiscoveryOutputPath
    Write-Host "Found $(@($domainDirectories).Count) domain(s)" -ForegroundColor Cyan

    foreach ($domainDir in $domainDirectories) {
        $domainName = Get-DomainNameFromPath -DomainDirName $domainDir.Name
        Write-Host "  Processing domain: $domainName" -ForegroundColor Gray

        foreach ($sectionDef in $config.Sections) {
            if ($Sections -and $Sections -notcontains $sectionDef.Id) { continue }

            # Only process per-domain sections in this loop
            $isPerDomain = $sectionDef.DataSource.PSObject.Properties['PerDomain'] -and $sectionDef.DataSource.PerDomain
            if (-not $isPerDomain) { continue }

            # Handle different data source patterns
            $csvPath = $null

            if ($sectionDef.DataSource.PSObject.Properties.Name -contains "Servers") {
                # Multi-file case (e.g., Computers: Servers + Workstations)
                $serversFile = Find-DomainCsv -Pattern $sectionDef.DataSource.Servers -DomainPath $domainDir.FullName -DomainName $domainName
                $workstationsFile = Find-DomainCsv -Pattern $sectionDef.DataSource.Workstations -DomainPath $domainDir.FullName -DomainName $domainName

                if ($serversFile -and $workstationsFile) {
                    $ctx = New-SectionContext -SectionDef $sectionDef -DomainName $domainName
                    $ctx.DataFiles.Servers = $serversFile
                    $ctx.DataFiles.Workstations = $workstationsFile
                    $sectionContexts += $ctx
                    Write-Host "    ✓ $($sectionDef.Title)" -ForegroundColor Green
                }
            }
            else {
                # Single pattern case
                $csvPath = Find-DomainCsv -Pattern $sectionDef.DataSource.Pattern -DomainPath $domainDir.FullName -DomainName $domainName

                if ($csvPath) {
                    $ctx = New-SectionContext -SectionDef $sectionDef -DomainName $domainName
                    $ctx.DataFiles.CsvPath = $csvPath
                    $sectionContexts += $ctx
                    Write-Host "    ✓ $($sectionDef.Title)" -ForegroundColor Green
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

        # Open template READ-ONLY (FileName, ConfirmConversions, ReadOnly, AddToRecentFiles)
        $template = $word.Documents.Open($TemplatePath, $false, $true, $false)

        # Create NEW document based on template (preserves styles and formatting)
        $doc = $word.Documents.Add($template.FullName)

        # Close template (no longer needed)
        $template.Close($false)
        Remove-AdComObject -ComObject $template
        $template = $null

        # Add sections to document
        $successCount = 0
        $failureCount = 0

        foreach ($ctx in $sectionContexts) {
            Write-Host "  Processing: $($ctx.Title)" -ForegroundColor Cyan

            try {
                # Get bookmark range if available
                $insertRange = $null
                if ($ctx.Bookmark) {
                    $insertRange = Get-AdBookmarkRange -Document $doc -BookmarkName $ctx.Bookmark
                    if (-not $insertRange) {
                        Write-Warning "Bookmark '$($ctx.Bookmark)' not found in template. Skipping section: $($ctx.Title)"
                        $failureCount++
                        continue
                    }
                }

                # Route to appropriate builder function
                $builderFunc = $ctx.Builder

                # Build parameters based on section type
                $builderParams = @{
                    Document       = $doc
                    Title          = $ctx.Title
                    TableStyleName = $TableStyleName
                }

                if ($HeaderFontColor) {
                    $builderParams.HeaderFontColor = $HeaderFontColor
                }

                # Add InsertRange if bookmark found
                if ($insertRange) {
                    $builderParams.InsertRange = $insertRange
                }

                # Multi-file builders (e.g., devices with Servers + Workstations)
                if ($ctx.DataFiles.ContainsKey("Servers")) {
                    $builderParams.ServersCsvPath = $ctx.DataFiles.Servers
                    $builderParams.WorkstationsCsvPath = $ctx.DataFiles.Workstations
                    if ($ctx.Parameters) {
                        foreach ($pkey in $ctx.Parameters.Keys) {
                            $builderParams[$pkey] = $ctx.Parameters[$pkey]
                        }
                    }
                }
                # Single-file builders
                else {
                    $builderParams.CsvPath = $ctx.DataFiles.CsvPath
                }

                # Call builder function
                if (Get-Command $builderFunc -ErrorAction SilentlyContinue) {
                    & $builderFunc @builderParams | Out-Null
                    $successCount++
                    Write-Host "    ✓ Added" -ForegroundColor Green
                }
                else {
                    Write-Warning "Builder function not found: $builderFunc"
                    $failureCount++
                }
            }
            catch {
                Write-Warning "Error processing section '$($ctx.Title)': $($_.Exception.Message)"
                $failureCount++
            }
        }

        # Save document to output path (NOT to template location)
        # Ensure output directory exists
        $OutputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        # SaveAs requires absolute path and proper format parameter
        # Format: 16 = wdFormatDocx (.docx), 12 = wdFormatDocument (.doc)
        $doc.SaveAs($OutputPath, 16)
        Write-Host "Document saved: $OutputPath" -ForegroundColor Green
        Write-Host "Success: $successCount | Failed: $failureCount" -ForegroundColor Cyan

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
