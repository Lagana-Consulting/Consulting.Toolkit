function Add-AdDomainInformation {
    <#
  .SYNOPSIS
  Creates a domain information table with domain-level metrics and configuration.

  .DESCRIPTION
  Generates a metric/value table showing domain information including:
  - Domain Name
  - Active Workstations
  - AD Recycle Bin Enabled
  - Disabled Users
  - Discovery Date
  - Domain Controller Count
  - Domain Count
  - Empty Groups
  - Enabled Users
  - Site Count
  - Stale Users
  - Subnet Count
  - Total Contacts
  - Total GPOs
  - Total Groups
  - Total OUs
  - Total Printers
  - Total Servers
  - Total Users
  - Total Workstations
  - Trust Count

  Calculates metrics by aggregating data from multiple CSV files in the domain folder.

  .PARAMETER Document
  The Word document object where the table will be inserted.

  .PARAMETER Title
  The caption/title for the table.

  .PARAMETER DomainFolderPath
  Path to the domain folder containing discovery CSV files (e.g., 20_domains/Domain-contoso.com).

  .PARAMETER ForestFolderPath
  Path to the forest-level folder (10_forest) for forest-wide metrics like site count, trust count, etc.

  .PARAMETER TableStyleName
  The Word table style to apply (e.g., "Grid Table 4 - Accent 1"). Optional.

  .PARAMETER InsertRange
  Optional Word range where the table should be inserted (e.g., from a bookmark).
  If not specified, inserts at the end of the document.

  .PARAMETER HeaderFontColor
  Optional color for the header row. Accepts hex string (e.g., "#003087") or OLE color integer.

  .EXAMPLE
  Add-AdDomainInformation -Document $word.ActiveDocument `
    -Title "Domain Information Summary" `
    -DomainFolderPath "C:\discovery\20_domains\Domain-contoso.com" `
    -ForestFolderPath "C:\discovery\10_forest" `
    -TableStyleName "Grid Table 4 - Accent 1"

  Creates domain information table by calculating metrics from discovery CSVs.

  .OUTPUTS
  Microsoft.Office.Interop.Word.Range
  Returns the range immediately after the inserted table for sequential insertions.
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [__ComObject]$Document,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$DomainFolderPath,

        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$ForestFolderPath,

        [string]$TableStyleName,

        [__ComObject]$InsertRange,

        $HeaderFontColor
    )

    # Calculate metrics from various CSV files
    $metrics = [ordered]@{}

    # Get domain name from Domain Summary CSV
    $domainSummaryCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Domain__Summary__Domain-*.csv" | Select-Object -First 1
    if ($domainSummaryCsv) {
        $domainInfo = Import-Csv -Path $domainSummaryCsv.FullName | Select-Object -First 1
        $metrics["DomainName"] = $domainInfo.DomainFqdn
    }
    else {
        $metrics["DomainName"] = "Unknown"
    }

    # Users metrics
    $usersCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Identity__Users__Domain-*.csv" | Select-Object -First 1
    if ($usersCsv) {
        $users = Import-Csv -Path $usersCsv.FullName
        $metrics["TotalUsers"] = $users.Count
        $metrics["EnabledUsers"] = @($users | Where-Object { $_.Enabled -eq 'True' }).Count
        $metrics["DisabledUsers"] = @($users | Where-Object { $_.Enabled -eq 'False' }).Count

        # Stale users (inactive > 90 days)
        $cutoffDate = (Get-Date).AddDays(-90)
        $metrics["StaleUsers"] = @($users | Where-Object {
                $_.LastLogonDate -and
                ([datetime]::Parse($_.LastLogonDate) -lt $cutoffDate)
            }).Count
    }
    else {
        $metrics["TotalUsers"] = 0
        $metrics["EnabledUsers"] = 0
        $metrics["DisabledUsers"] = 0
        $metrics["StaleUsers"] = 0
    }

    # Workstations metrics
    $workstationsCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Identity__ComputersWorkstations__Domain-*.csv" | Select-Object -First 1
    if ($workstationsCsv) {
        $workstations = Import-Csv -Path $workstationsCsv.FullName
        $metrics["TotalWorkstations"] = $workstations.Count

        # Active workstations (logged on in last 30 days)
        $activeCutoff = (Get-Date).AddDays(-30)
        $metrics["ActiveWorkstations"] = @($workstations | Where-Object {
                $_.LastLogonDate -and
                ([datetime]::Parse($_.LastLogonDate) -gt $activeCutoff)
            }).Count
    }
    else {
        $metrics["TotalWorkstations"] = 0
        $metrics["ActiveWorkstations"] = 0
    }

    # Servers metrics
    $serversCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Identity__ComputersServers__Domain-*.csv" | Select-Object -First 1
    if ($serversCsv) {
        $servers = Import-Csv -Path $serversCsv.FullName
        $metrics["TotalServers"] = $servers.Count
    }
    else {
        $metrics["TotalServers"] = 0
    }

    # Groups metrics
    $groupsCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Identity__Groups__Domain-*.csv" | Select-Object -First 1
    if ($groupsCsv) {
        $groups = Import-Csv -Path $groupsCsv.FullName
        $metrics["TotalGroups"] = $groups.Count
        $metrics["EmptyGroups"] = @($groups | Where-Object { -not $_.Members -or $_.Members -eq '' }).Count
    }
    else {
        $metrics["TotalGroups"] = 0
        $metrics["EmptyGroups"] = 0
    }

    # Contacts
    $contactsCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Identity__Contacts__Domain-*.csv" | Select-Object -First 1
    if ($contactsCsv) {
        $contacts = Import-Csv -Path $contactsCsv.FullName
        $metrics["TotalContacts"] = $contacts.Count
    }
    else {
        $metrics["TotalContacts"] = 0
    }

    # GPOs
    $gposCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Config__GPOInventory__Domain-*.csv" | Select-Object -First 1
    if ($gposCsv) {
        $gpos = Import-Csv -Path $gposCsv.FullName
        $metrics["TotalGPOs"] = $gpos.Count
    }
    else {
        $metrics["TotalGPOs"] = 0
    }

    # OUs
    $ousCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Identity__OrganizationalUnits__Domain-*.csv" | Select-Object -First 1
    if ($ousCsv) {
        $ous = Import-Csv -Path $ousCsv.FullName
        $metrics["TotalOUs"] = $ous.Count
    }
    else {
        $metrics["TotalOUs"] = 0
    }

    # Printers
    $printersCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Identity__Printers__Domain-*.csv" | Select-Object -First 1
    if ($printersCsv) {
        $printers = Import-Csv -Path $printersCsv.FullName
        $metrics["TotalPrinters"] = $printers.Count
    }
    else {
        $metrics["TotalPrinters"] = 0
    }

    # Domain Controllers
    $dcsCsv = Get-ChildItem -Path $DomainFolderPath -Filter "*__Infrastructure__DomainControllers__Domain-*.csv" | Select-Object -First 1
    if ($dcsCsv) {
        $dcs = Import-Csv -Path $dcsCsv.FullName
        $metrics["DomainControllerCount"] = $dcs.Count
    }
    else {
        $metrics["DomainControllerCount"] = 0
    }

    # Forest-level metrics (if ForestFolderPath provided)
    if ($ForestFolderPath) {
        # Sites
        $sitesCsv = Get-ChildItem -Path $ForestFolderPath -Filter "*__Infrastructure__Sites__Forest.csv" | Select-Object -First 1
        if ($sitesCsv) {
            $sites = Import-Csv -Path $sitesCsv.FullName
            $metrics["SiteCount"] = $sites.Count
        }
        else {
            $metrics["SiteCount"] = 0
        }

        # Subnets
        $subnetsCsv = Get-ChildItem -Path $ForestFolderPath -Filter "*__Infrastructure__Subnets__Forest.csv" | Select-Object -First 1
        if ($subnetsCsv) {
            $subnets = Import-Csv -Path $subnetsCsv.FullName
            $metrics["SubnetCount"] = $subnets.Count
        }
        else {
            $metrics["SubnetCount"] = 0
        }

        # Trusts
        $trustsCsv = Get-ChildItem -Path $ForestFolderPath -Filter "*__Infrastructure__Trusts__Forest.csv" | Select-Object -First 1
        if ($trustsCsv) {
            $trusts = Import-Csv -Path $trustsCsv.FullName
            $metrics["TrustCount"] = $trusts.Count
        }
        else {
            $metrics["TrustCount"] = 0
        }

        # Domain Count (from forest summary)
        $forestSummaryCsv = Get-ChildItem -Path $ForestFolderPath -Filter "*__Forest__Summary__Forest.csv" | Select-Object -First 1
        if ($forestSummaryCsv) {
            $forestInfo = Import-Csv -Path $forestSummaryCsv.FullName | Select-Object -First 1
            $metrics["DomainCount"] = $forestInfo.DomainCount
        }
        else {
            $metrics["DomainCount"] = 1
        }
    }
    else {
        $metrics["SiteCount"] = "N/A"
        $metrics["SubnetCount"] = "N/A"
        $metrics["TrustCount"] = "N/A"
        $metrics["DomainCount"] = 1
    }

    # AD Recycle Bin status (from forest config)
    $metrics["ADRecycleBinEnabled"] = "Unknown"

    # Discovery Date
    $metrics["DiscoveryDate"] = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Determine insert position
    if ($InsertRange) {
        $range = $InsertRange
    }
    else {
        $range = $Document.Content
        $range.Collapse(1)
    }

    # Add caption paragraph
    $range.InsertAfter("`r`n")
    $range.Collapse(1)
    $caption = $range.Paragraphs.Add($range)
    $caption.Range.Text = $Title
    $caption.Style = "Caption"
    $caption.Range.InsertParagraphAfter()

    # Create table
    $numRows = $metrics.Count + 1  # +1 for header
    $numCols = 2
    $tableRange = $caption.Range.Next()
    $tableRange.Collapse(1)
    $table = $Document.Tables.Add($tableRange, $numRows, $numCols)

    # Set table content style to Normal before applying table style
    $table.Range.Style = "Normal"


    # Header row
    $table.Cell(1, 1).Range.Text = "Metric"
    $table.Cell(1, 2).Range.Text = "Value"
    $table.Rows.Item(1).HeadingFormat = -1

    # Data rows
    $rowIndex = 2
    foreach ($key in $metrics.Keys) {
        $table.Cell($rowIndex, 1).Range.Text = $key
        $table.Cell($rowIndex, 2).Range.Text = $metrics[$key]
        $rowIndex++
    }

    # Apply table style
    if ($TableStyleName) {
        $style = Get-AdWordTableStyle -Document $Document -TableStyleName $TableStyleName
        if ($style) {
            $table.Style = $style
        }
    }

    $table.AutoFitBehavior(1)

    # Apply header color
    if ($HeaderFontColor) {
        Set-AdHeaderFontColor -Table $table -Color $HeaderFontColor
    }

    # Return next insertion point
    $nextRange = $Document.Range($table.Range.End, $table.Range.End)
    return $nextRange
}




