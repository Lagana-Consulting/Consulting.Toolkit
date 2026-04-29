function Invoke-ADOnlyAssessment {
    <#
  .SYNOPSIS
  Runs an Active Directory-only assessment using a JSON config and Word template.

  .DESCRIPTION
  Loads a JSON configuration that defines AD-specific sections, data sources, and bookmarks,
  then produces a Word report by inserting AD tables into the specified template.
  This function processes only Active Directory tables (not Entra/M365).

  .PARAMETER ConfigPath
  Path to the assessment JSON configuration file.

  .PARAMETER OutputPath
  Optional override for output document path.

  .PARAMETER TemplatePath
  Optional override for the Word template path defined in the config.

  .PARAMETER UseBundledDiscoveryTemplate
  Use the bundled "Discovery and Assessment Findings Report" Word template from the module config folder.

  .PARAMETER UseBundledSummaryTemplate
  Use the bundled "Assessment Summary and Migration Process" Word template from the module config folder.

  .PARAMETER Visible
  Show Word UI while generating the report.

  .EXAMPLE
  Invoke-ADOnlyAssessment -ConfigPath 'C:\Assessments\ADAssessmentConfig.json'

  .EXAMPLE
  Invoke-ADOnlyAssessment -ConfigPath 'C:\Assessments\Config.json' -Visible

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  System.String - Path to the generated assessment document.

  .NOTES
  Requires Word.Application COM object and properly formatted JSON configuration.
  Skips any Entra/M365 sections found in config.

  .LINK
  Invoke-AZOnlyAssessment
  Invoke-FullAssessment
  Invoke-AdAssessment
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [string]$TemplatePath,

        [switch]$UseBundledDiscoveryTemplate,

        [switch]$UseBundledSummaryTemplate,

        [switch]$Visible
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $configJson = Get-Content -Path $ConfigPath -Raw
    $config = $configJson | ConvertFrom-Json

    $templatePath = Resolve-AdAssessmentTemplatePath -TemplatePath $(if ($TemplatePath) { $TemplatePath } else { $config.TemplatePath }) -UseBundledDiscoveryTemplate:$UseBundledDiscoveryTemplate -UseBundledSummaryTemplate:$UseBundledSummaryTemplate
    $outputRoot = $config.OutputRoot
    $customer = $config.Customer
    $tableStyle = $config.TableStyleName
    $sections = $config.Sections

    if (-not $OutputPath) {
        if (-not (Test-Path $outputRoot)) {
            New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null
        }
        $reportDate = Get-Date
        $outputFile = "{0}_AD_Assessment_{1:yyyyMMdd}.docx" -f $customer.Name, $reportDate
        $OutputPath = Join-Path $outputRoot $outputFile
    }

    $word = $null
    $doc = $null

    try {
        $word = New-AdWordInstance -Visible:$Visible

        # Open template read-only then save as output
        $doc = $word.Documents.Open($templatePath, $false, $true)
        $doc.SaveAs([ref]$OutputPath) | Out-Null
        $doc.Close($false) | Out-Null

        # Reopen output for editing
        $doc = $word.Documents.Open($OutputPath, $false, $false)

        # Placeholder replacements (if provided)
        if ($config.Placeholders) {
            foreach ($key in $config.Placeholders.PSObject.Properties.Name) {
                $value = [string]$config.Placeholders.$key
                $range = $doc.Content
                $find = $range.Find
                $find.ClearFormatting() | Out-Null
                $find.Replacement.ClearFormatting() | Out-Null
                $find.Text = [string]$key
                $find.Replacement.Text = $value
                $null = $find.Execute($key, $false, $false, $false, $false, $false, $true, 1, $false, $value, 2)
            }
        }

        # AD-specific section processing (skip Az* prefixed functions)
        $adOnlyPatterns = @('Add-Ad', 'Add-AzEntraUser', 'Add-AzEntraGuest')  # Include Entra user-focused functions

        foreach ($section in $sections) {
            # Skip M365-only sections
            $tableType = [string]$section.TableType
            if ($tableType -match '(M365|Mailbox|OneDrive|Teams|SharePoint)') {
                Write-Verbose "Skipping M365 section: $tableType"
                continue
            }

            $bookmark = [string]$section.Bookmark
            $range = Get-AdBookmarkRange -Document $doc -BookmarkName $bookmark
            if (-not $range) {
                Write-Warning "Bookmark '$bookmark' not found in template."
                continue
            }

            $range.Text = ""
            $range.Collapse(0) | Out-Null

            $csvPath = [string]$section.CsvPath
            $title = [string]$section.Title
            $columns = $section.Columns
            $headerColor = [string]$section.HeaderFontColor

            if (-not (Test-Path $csvPath)) {
                Write-Warning "CSV not found: $csvPath"
                continue
            }

            $data = Import-Csv $csvPath
            if (-not $data -or $data.Count -eq 0) {
                Write-Warning "CSV '$csvPath' is empty."
                continue
            }

            $hRange = $range.Duplicate()
            $para = $hRange.Paragraphs.Add()
            $para.Range.Text = $title
            $para.Range.Style = "Caption"
            $para.Range.InsertParagraphAfter() | Out-Null

            $afterHeading = $para.Range.Duplicate()
            $afterHeading.Collapse(0) | Out-Null

            $availableCols = $data[0].PSObject.Properties.Name
            $headerMap = [ordered]@{}

            if ($columns) {
                if ($columns -is [System.Management.Automation.PSCustomObject]) {
                    $tmp = [ordered]@{}
                    foreach ($p in $columns.PSObject.Properties) { $tmp[$p.Name] = $p.Value }
                    $columns = $tmp
                }

                if ($columns -is [System.Collections.IDictionary]) {
                    foreach ($k in $columns.Keys) {
                        if ($availableCols -contains $columns[$k]) { $headerMap[$k] = $columns[$k] }
                    }
                }
                elseif ($columns -is [System.Collections.IEnumerable]) {
                    foreach ($c in $columns) {
                        if ($availableCols -contains $c) { $headerMap[$c] = $c }
                    }
                }
            }

            if ($headerMap.Count -eq 0) {
                foreach ($col in $availableCols) { $headerMap[$col] = $col }
            }

            $headers = @($headerMap.Keys)
            $rows = $data.Count + 1
            $cols = $headers.Count
            $table = $doc.Tables.Add($afterHeading, $rows, $cols)
            $table.Range.Style = "Normal"

            $styleObj = Get-AdWordTableStyle -Document $doc -TableStyleName $tableStyle
            if ($styleObj) { $table.Style = $styleObj }

            for ($c = 0; $c -lt $cols; $c++) {
                $cellRange = $table.Cell(1, $c + 1).Range
                $cellRange.Text = [string]$headers[$c]
                $cellRange.Bold = $true
                Set-AdHeaderFontColor -Range $cellRange -HeaderFontColor $headerColor
            }

            $r = 2
            foreach ($row in $data) {
                for ($c = 0; $c -lt $cols; $c++) {
                    $sourceCol = $headerMap[$headers[$c]]
                    $table.Cell($r, $c + 1).Range.Text = [string]$row.$sourceCol
                }
                $r++
            }

            $table.Range.InsertParagraphAfter() | Out-Null
        }

        $doc.Save()
        Write-Host "AD Assessment document created: $OutputPath" -ForegroundColor Green
        return $OutputPath
    }
    finally {
        if ($doc) { $doc.Close($false) | Out-Null }
        if ($word) { $word.Quit() | Out-Null }

        if ($doc) { Remove-AdComObject -ComObject $doc }
        if ($word) { Remove-AdComObject -ComObject $word }

        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}
