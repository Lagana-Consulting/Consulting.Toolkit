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

    try { return $Document.Styles.Item($TableStyleName) } catch { return $null }
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
        [Parameter(Mandatory)] $Range,
        [string] $HeaderFontColor
    )

    if (-not $HeaderFontColor) { return }

    if ($HeaderFontColor -match '^#?[0-9A-Fa-f]{6}$') {
        $hex = $HeaderFontColor.TrimStart('#')
        $rgb = [Convert]::ToInt32($hex, 16)
        $Range.Font.TextColor.RGB = $rgb
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
