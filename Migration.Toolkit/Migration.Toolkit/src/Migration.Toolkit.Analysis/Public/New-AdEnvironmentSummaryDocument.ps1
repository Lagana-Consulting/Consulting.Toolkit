function New-AdEnvironmentSummaryDocument {
    <#
    .SYNOPSIS
    Creates a professional Word document with environment summary tables.

    .DESCRIPTION
    Generates a Word document containing formatted tables summarizing AD environment data.
    Supports multiple source and target environments from discovery outputs.

    .PARAMETER SourceRunRoot
    Array of paths to source discovery output folders.

    .PARAMETER TargetRunRoot
    Array of paths to target discovery output folders.

    .PARAMETER SourceEnvironmentNames
    Optional custom names for source environments. Default: Source 1, Source 2, etc.

    .PARAMETER TargetEnvironmentNames
    Optional custom names for target environments. Default: Target 1, Target 2, etc.

    .PARAMETER OutputPath
    Path where the Word document will be saved. Default: current directory with timestamp.

    .PARAMETER Title
    Document title. Default: "Active Directory Environment Summary"

    .EXAMPLE
    New-AdEnvironmentSummaryDocument -SourceRunRoot @("C:\discovery\source1", "C:\discovery\source2") -TargetRunRoot @("C:\discovery\target") -OutputPath "C:\output\summary.docx"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SourceRunRoot,

        [Parameter(Mandatory)]
        [string[]]$TargetRunRoot,

        [Parameter()]
        [string[]]$SourceEnvironmentNames,

        [Parameter()]
        [string[]]$TargetEnvironmentNames,

        [Parameter()]
        [string]$OutputPath = (Join-Path (Get-Location).Path "AD_Environment_Summary_$(Get-Date -Format 'yyyyMMdd-HHmmss').docx"),

        [Parameter()]
        [string]$Title = "Active Directory Environment Summary"
    )

    # Verify Word is available
    try {
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
    }
    catch {
        throw "Microsoft Word is not installed or not available. This function requires Word to generate documents."
    }

    # Set default environment names if not provided
    if (-not $SourceEnvironmentNames -or $SourceEnvironmentNames.Count -eq 0) {
        $SourceEnvironmentNames = @(1..$SourceRunRoot.Count | ForEach-Object { "Source $_" })
    }

    if (-not $TargetEnvironmentNames -or $TargetEnvironmentNames.Count -eq 0) {
        $TargetEnvironmentNames = @(1..$TargetRunRoot.Count | ForEach-Object { "Target $_" })
    }

    try {
        $word.Visible = $false
        $doc = $word.Documents.Add()
        $selection = $word.Selection

        # Add title
        $selection.Font.Size = 16
        $selection.Font.Bold = $true
        $selection.TypeText($Title)
        $selection.TypeParagraph()
        $selection.TypeParagraph()
        $selection.Font.Size = 11
        $selection.Font.Bold = $false

        # Helper function to load environment data from discovery outputs
        function Get-EnvironmentData {
            param([string]$RunRoot)

            $result = @{
                Domains               = @()
                DomainControllers     = @()
                ObjectCounts          = @{ Users = 0; Groups = 0; Computers = 0; Contacts = 0 }
                ForestFunctionalLevel = "Unknown"
            }

            $domainsRoot = Join-Path $RunRoot '20_domains'
            $forestRoot = Join-Path $RunRoot '10_forest'
            $forestRoles = @{}

            function Test-HostMatch {
                param(
                    [string]$Candidate,
                    [string[]]$DcNames
                )

                if (-not $Candidate) {
                    return $false
                }

                $candidateUpper = $Candidate.ToUpperInvariant()
                if ($DcNames -contains $candidateUpper) {
                    return $true
                }

                $short = $candidateUpper.Split('.')[0]
                return $DcNames -contains $short
            }

            # Get forest functional level
            if (Test-Path $forestRoot) {
                $forestSummaryFiles = Get-ChildItem -Path $forestRoot -Filter '*Forest__Summary*.csv' -ErrorAction SilentlyContinue
                if ($forestSummaryFiles) {
                    $forestData = Import-Csv -Path $forestSummaryFiles[0].FullName -ErrorAction SilentlyContinue
                    if ($forestData) {
                        $result['ForestFunctionalLevel'] = $forestData[0].ForestMode
                        $forestRoles['SchemaMaster'] = $forestData[0].SchemaMaster
                        $forestRoles['DomainNamingMaster'] = $forestData[0].DomainNamingMaster
                    }
                }
            }

            # Get domain data
            if (Test-Path $domainsRoot) {
                Get-ChildItem -Path $domainsRoot -Directory | ForEach-Object {
                    $domainFolder = $_.FullName
                    $domainSummary = $null

                    # Domain summary
                    $summaryFiles = Get-ChildItem -Path $domainFolder -Filter '*Domain__Summary*.csv' -ErrorAction SilentlyContinue
                    if ($summaryFiles) {
                        $summaryData = Import-Csv -Path $summaryFiles[0].FullName -ErrorAction SilentlyContinue
                        if ($summaryData) {
                            $domainSummary = $summaryData[0]
                            $result['Domains'] += @{
                                FQDN            = $summaryData[0].DomainFqdn
                                NetBIOS         = $summaryData[0].NetBIOSName
                                FunctionalLevel = $summaryData[0].DomainMode
                            }
                        }
                    }

                    # Domain controllers
                    $dcFiles = Get-ChildItem -Path $domainFolder -Filter '*DomainControllers*.csv' -ErrorAction SilentlyContinue
                    if ($dcFiles) {
                        $dcData = Import-Csv -Path $dcFiles[0].FullName -ErrorAction SilentlyContinue
                        if ($dcData) {
                            $dcData | ForEach-Object {
                                $dcNames = @($_.HostName, $_.Name) | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() }
                                $fsmoRoles = @()

                                if ($domainSummary) {
                                    if (Test-HostMatch -Candidate $domainSummary.PdcEmulator -DcNames $dcNames) { $fsmoRoles += 'PDC' }
                                    if (Test-HostMatch -Candidate $domainSummary.RidMaster -DcNames $dcNames) { $fsmoRoles += 'RID' }
                                    if (Test-HostMatch -Candidate $domainSummary.InfrastructureMaster -DcNames $dcNames) { $fsmoRoles += 'Infrastructure' }
                                }

                                if (Test-HostMatch -Candidate $forestRoles['SchemaMaster'] -DcNames $dcNames) { $fsmoRoles += 'Schema' }
                                if (Test-HostMatch -Candidate $forestRoles['DomainNamingMaster'] -DcNames $dcNames) { $fsmoRoles += 'DomainNaming' }

                                $role = if ($fsmoRoles.Count -gt 0) { ($fsmoRoles -join ', ') } else { 'Replica' }
                                $result['DomainControllers'] += @{
                                    Name = $_.HostName
                                    IP   = $_.IPv4Address
                                    OS   = $_.OperatingSystem
                                    Role = $role
                                }
                            }
                        }
                    }

                    # Object counts
                    $userFiles = Get-ChildItem -Path $domainFolder -Filter '*Identity__Users*.csv' -ErrorAction SilentlyContinue
                    if ($userFiles) {
                        $userData = @(Import-Csv -Path $userFiles[0].FullName -ErrorAction SilentlyContinue)
                        $result['ObjectCounts']['Users'] += $userData.Count
                    }

                    $groupFiles = Get-ChildItem -Path $domainFolder -Filter '*Identity__Groups*.csv' -ErrorAction SilentlyContinue
                    if ($groupFiles) {
                        $groupData = @(Import-Csv -Path $groupFiles[0].FullName -ErrorAction SilentlyContinue)
                        $result['ObjectCounts']['Groups'] += $groupData.Count
                    }

                    $compFiles = Get-ChildItem -Path $domainFolder -Filter '*Identity__ComputersAll*.csv' -ErrorAction SilentlyContinue
                    if ($compFiles) {
                        $compData = @(Import-Csv -Path $compFiles[0].FullName -ErrorAction SilentlyContinue)
                        $result['ObjectCounts']['Computers'] += $compData.Count
                    }
                }
            }

            return $result
        }

        # Helper function to add environment section with tables
        function Add-EnvironmentSection {
            param(
                [string]$EnvironmentName,
                [hashtable]$EnvironmentData,
                [string]$SectionType
            )

            # Section header
            $selection.Font.Size = 14
            $selection.Font.Bold = $true
            $selection.TypeText("$EnvironmentName ($SectionType)")
            $selection.TypeParagraph()

            $selection.Font.Size = 12
            $selection.Font.Bold = $true
            $selection.TypeText("Active Directory Summary")
            $selection.TypeParagraph()

            $selection.Font.Size = 11
            $selection.Font.Bold = $false

            # Add Domains Table
            if ($EnvironmentData['Domains'] -and $EnvironmentData['Domains'].Count -gt 0) {
                $selection.TypeText("Domains")
                $selection.TypeParagraph()

                try {
                    $rowCount = $EnvironmentData['Domains'].Count + 1
                    $range = $selection.Range
                    $range.Collapse(1) # wdCollapseEnd
                    $table = $doc.Tables.Add($range, $rowCount, 4)

                    if ($table) {
                        try {
                            $table.Style = "Light Grid Accent 1"
                        }
                        catch {
                            $table.Style = "Table Grid"
                        }

                        # Header row
                        $table.Cell(1, 1).Range.Text = "Domain FQDN"
                        $table.Cell(1, 2).Range.Text = "NetBIOS"
                        $table.Cell(1, 3).Range.Text = "Mode"
                        $table.Cell(1, 4).Range.Text = "Forest Level"

                        # Data rows
                        $rowNum = 2
                        $EnvironmentData['Domains'] | ForEach-Object {
                            $table.Cell($rowNum, 1).Range.Text = $_.FQDN
                            $table.Cell($rowNum, 2).Range.Text = $_.NetBIOS
                            $table.Cell($rowNum, 3).Range.Text = $_.FunctionalLevel
                            $table.Cell($rowNum, 4).Range.Text = $EnvironmentData['ForestFunctionalLevel']
                            $rowNum++
                        }

                        # Move selection after table
                        $selection.SetRange($table.Range.End, $table.Range.End)
                        $selection.TypeParagraph()
                    }
                }
                catch {
                    Write-Warning "Failed to create domains table: $_"
                }
                $selection.TypeParagraph()
            }

            # Add Domain Controllers Table
            if ($EnvironmentData['DomainControllers'] -and $EnvironmentData['DomainControllers'].Count -gt 0) {
                $selection.TypeText("Domain Controllers")
                $selection.TypeParagraph()

                try {
                    $rowCount = $EnvironmentData['DomainControllers'].Count + 1
                    $range = $selection.Range
                    $range.Collapse(1) # wdCollapseEnd
                    $table = $doc.Tables.Add($range, $rowCount, 4)

                    if ($table) {
                        try {
                            $table.Style = "Light Grid Accent 1"
                        }
                        catch {
                            $table.Style = "Table Grid"
                        }

                        # Header row
                        $table.Cell(1, 1).Range.Text = "Hostname"
                        $table.Cell(1, 2).Range.Text = "IP Address"
                        $table.Cell(1, 3).Range.Text = "Operating System"
                        $table.Cell(1, 4).Range.Text = "Role"

                        # Data rows
                        $rowNum = 2
                        $EnvironmentData['DomainControllers'] | ForEach-Object {
                            $table.Cell($rowNum, 1).Range.Text = $_.Name
                            $table.Cell($rowNum, 2).Range.Text = $_.IP
                            $table.Cell($rowNum, 3).Range.Text = $_.OS
                            $table.Cell($rowNum, 4).Range.Text = $_.Role
                            $rowNum++
                        }

                        # Move selection after table
                        $selection.SetRange($table.Range.End, $table.Range.End)
                        $selection.TypeParagraph()
                    }
                }
                catch {
                    Write-Warning "Failed to create DC table: $_"
                }
                $selection.TypeParagraph()
            }

            # Add Object Counts Table
            if ($EnvironmentData['ObjectCounts'] -and ($EnvironmentData['ObjectCounts']['Users'] -gt 0 -or $EnvironmentData['ObjectCounts']['Groups'] -gt 0 -or $EnvironmentData['ObjectCounts']['Computers'] -gt 0)) {
                $selection.TypeText("Object Counts")
                $selection.TypeParagraph()

                try {
                    $range = $selection.Range
                    $range.Collapse(1) # wdCollapseEnd
                    $table = $doc.Tables.Add($range, 2, 4)

                    if ($table) {
                        try {
                            $table.Style = "Light Grid Accent 1"
                        }
                        catch {
                            $table.Style = "Table Grid"
                        }

                        # Header row
                        $table.Cell(1, 1).Range.Text = "Users"
                        $table.Cell(1, 2).Range.Text = "Groups"
                        $table.Cell(1, 3).Range.Text = "Computers"
                        $table.Cell(1, 4).Range.Text = "Contacts"

                        # Data row
                        $table.Cell(2, 1).Range.Text = [string]$EnvironmentData['ObjectCounts']['Users']
                        $table.Cell(2, 2).Range.Text = [string]$EnvironmentData['ObjectCounts']['Groups']
                        $table.Cell(2, 3).Range.Text = [string]$EnvironmentData['ObjectCounts']['Computers']
                        $table.Cell(2, 4).Range.Text = [string]$EnvironmentData['ObjectCounts']['Contacts']

                        # Move selection after table
                        $selection.SetRange($table.Range.End, $table.Range.End)
                        $selection.TypeParagraph()
                    }
                }
                catch {
                    Write-Warning "Failed to create object counts table: $_"
                }
                $selection.TypeParagraph()
            }

            $selection.TypeParagraph()
        }

        # Process source environments
        for ($i = 0; $i -lt $SourceRunRoot.Count; $i++) {
            $sourceData = Get-EnvironmentData -RunRoot $SourceRunRoot[$i]
            $sourceName = if ($SourceEnvironmentNames -and $i -lt $SourceEnvironmentNames.Count) { $SourceEnvironmentNames[$i] } else { "Source $($i + 1)" }
            Add-EnvironmentSection -EnvironmentName $sourceName -EnvironmentData $sourceData -SectionType "Source"
        }

        # Process target environments
        for ($i = 0; $i -lt $TargetRunRoot.Count; $i++) {
            $targetData = Get-EnvironmentData -RunRoot $TargetRunRoot[$i]
            $targetName = if ($TargetEnvironmentNames -and $i -lt $TargetEnvironmentNames.Count) { $TargetEnvironmentNames[$i] } else { "Target $($i + 1)" }
            Add-EnvironmentSection -EnvironmentName $targetName -EnvironmentData $targetData -SectionType "Target"
        }

        # Save document
        $doc.SaveAs([ref]$OutputPath)
        $doc.Close()

        Write-Host "Environment summary document created: $OutputPath" -ForegroundColor Green
        return $OutputPath
    }
    finally {
        if ($word) {
            $word.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
        }
    }
}
