function Export-AppIcon {
    <#
    .SYNOPSIS
        Extracts the associated icon of a file (e.g. an .exe) and saves it as an image.
    .NOTES
        Adapted from "Extracting Icons with PowerShell" by Jeff Hicks:
        https://jdhitsolutions.com/blog/powershell/7931/extracting-icons-with-powershell/
        Inspired by https://community.spiceworks.com/topic/592770-extract-icon-from-exe-powershell
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -LiteralPath $_ })]
        [string]$Path,

        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$Destination = '.',

        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateSet('ico', 'bmp', 'png', 'jpg', 'gif')]
        [string]$Format = 'png'
    )

    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    $imageFormat = switch ($Format) {
        'ico' { [System.Drawing.Imaging.ImageFormat]::Icon }
        'bmp' { [System.Drawing.Imaging.ImageFormat]::Bmp }
        'png' { [System.Drawing.Imaging.ImageFormat]::Png }
        'jpg' { [System.Drawing.Imaging.ImageFormat]::Jpeg }
        'gif' { [System.Drawing.Imaging.ImageFormat]::Gif }
    }

    $file = Get-Item -LiteralPath $Path
    $base = if ($Name) { $Name } else { $file.BaseName }
    $out = Join-Path -Path (Convert-Path -LiteralPath $Destination) -ChildPath "$base.$Format"

    Write-Verbose "Extracting icon from '$($file.FullName)' to '$out'"
    $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($file.FullName)
    if (-not $icon) {
        Write-Warning "No associated icon image found in $($file.FullName)"
        return
    }

    try {
        $bitmap = $icon.ToBitmap()
        try {
            $bitmap.Save($out, $imageFormat)
        }
        finally {
            $bitmap.Dispose()
        }
    }
    finally {
        $icon.Dispose()
    }

    Get-Item -LiteralPath $out
}
