function New-AdWordInstance {
    [CmdletBinding()]
    param(
        [switch]$Visible
    )

    $word = New-Object -ComObject Word.Application
    $word.Visible = [bool]$Visible
    $word.DisplayAlerts = 0
    return $word
}

function Get-AdWordTableStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $TableStyleName
    )

    # Get table style from Styles collection (matches old working script pattern)
    try {
        $style = $Document.Styles.Item($TableStyleName)
    }
    catch {
        $style = $null
    }

    if (-not $style) {
        Write-Warning "Table style '$TableStyleName' not found in template."
    }

    return $style
}

function Get-AdBookmarkRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Document,
        [Parameter(Mandatory)][string] $BookmarkName
    )

    if (-not $Document.Bookmarks.Exists($BookmarkName)) {
        return $null
    }

    return $Document.Bookmarks.Item($BookmarkName).Range.Duplicate()
}

function Set-AdHeaderFontColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Range')] $Range,
        [Parameter(Mandatory, ParameterSetName = 'Table')] $Table,
        [string] $HeaderFontColor,
        [string] $Color  # Alias for backward compatibility
    )

    # Support both parameter names for backward compatibility
    if ($Color -and -not $HeaderFontColor) {
        $HeaderFontColor = $Color
    }

    if (-not $HeaderFontColor) { return }

    # Handle table parameter - apply to all cells in first row
    if ($Table) {
        $headerRowCellCount = $Table.Rows.Item(1).Cells.Count
        for ($i = 1; $i -le $headerRowCellCount; $i++) {
            $cellRange = $Table.Cell(1, $i).Range
            if ($HeaderFontColor -match '^#?[0-9A-Fa-f]{6}$') {
                $hex = $HeaderFontColor.TrimStart('#')
                $rgb = [Convert]::ToInt32($hex, 16)
                $cellRange.Font.Color = $rgb
            }
            else {
                $cellRange.Font.Color = [int]$HeaderFontColor
            }
        }
        return
    }

    # Handle range parameter - apply to single range
    if ($HeaderFontColor -match '^#?[0-9A-Fa-f]{6}$') {
        $hex = $HeaderFontColor.TrimStart('#')
        $rgb = [Convert]::ToInt32($hex, 16)
        $Range.Font.Color = $rgb
    }
    else {
        $Range.Font.Color = [int]$HeaderFontColor
    }
}

function Remove-AdComObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ComObject)

    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) | Out-Null } catch { }
}
