function Export-AppIcon {
    <#
    .SYNOPSIS
        Extracts the largest icon of a file (.exe, .dll, .ico or an image) and saves it as an image.
    .DESCRIPTION
        For .exe and .dll files the icon group resources are read directly: -Index selects the n-th
        group (0 based); a negative -Index is a resource ID, as in the Windows DisplayIcon syntax
        'file.exe,-101'. The largest entry of the group is used (up to 256 px, higher bit depth wins
        a tie). A PNG-compressed entry is written as-is when the format is png and it is not larger
        than -MaxSize. A file without icon groups falls back to the shell's associated icon (32 px).
        .ico files use their largest frame; .png, .jpg and .bmp files are loaded as images. Images
        larger than -MaxSize are scaled down with high-quality bicubic resampling, never up.
        Returns the written file with the NoteProperties IconWidth and IconHeight, or writes a
        warning and returns nothing when no icon can be read.
    .NOTES
        Adapted from "Extracting Icons with PowerShell" by Jeff Hicks:
        https://jdhitsolutions.com/blog/powershell/7931/extracting-icons-with-powershell/
        Inspired by https://community.spiceworks.com/topic/592770-extract-icon-from-exe-powershell

        Twin file: psadt-package-to-intune\PSADTIntune\Private\Export-AppIcon.ps1. Keep both identical.
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
        [string]$Format = 'png',

        # Icon group number (0 based), or with a negative value the resource ID of the group
        [int]$Index = 0,

        # Larger icons are scaled down to this size (pixels)
        [ValidateRange(1, 4096)]
        [int]$MaxSize = 256
    )

    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    if (-not ('ExportAppIconNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class ExportAppIconNative
{
    delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool EnumResourceNames(IntPtr hModule, IntPtr lpszType, EnumResNameProc lpEnumFunc, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr FindResource(IntPtr hModule, IntPtr lpName, IntPtr lpType);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);

    [DllImport("kernel32.dll")]
    static extern IntPtr LockResource(IntPtr hResData);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint SizeofResource(IntPtr hModule, IntPtr hResInfo);

    static byte[] ReadResource(IntPtr module, object name, int type)
    {
        IntPtr namePtr = IntPtr.Zero;
        bool allocated = false;
        if (name is int) { namePtr = (IntPtr)(int)name; }
        else { namePtr = Marshal.StringToHGlobalUni((string)name); allocated = true; }
        try
        {
            IntPtr info = FindResource(module, namePtr, (IntPtr)type);
            if (info == IntPtr.Zero) { return null; }
            uint size = SizeofResource(module, info);
            IntPtr loaded = LoadResource(module, info);
            if (loaded == IntPtr.Zero || size == 0) { return null; }
            IntPtr locked = LockResource(loaded);
            if (locked == IntPtr.Zero) { return null; }
            byte[] data = new byte[size];
            Marshal.Copy(locked, data, 0, (int)size);
            return data;
        }
        finally
        {
            if (allocated) { Marshal.FreeHGlobal(namePtr); }
        }
    }

    // Returns the data of the largest RT_ICON image of an icon group, or null when the file has no
    // such group. index >= 0 selects the n-th group; index < 0 selects the group with ID -index.
    public static byte[] GetBestIcon(string path, int index)
    {
        // LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE
        IntPtr module = LoadLibraryEx(path, IntPtr.Zero, 0x22);
        if (module == IntPtr.Zero) { return null; }
        try
        {
            List<object> groups = new List<object>();
            EnumResourceNames(module, (IntPtr)14, delegate (IntPtr m, IntPtr t, IntPtr n, IntPtr l)
            {
                if ((n.ToInt64() >> 16) == 0) { groups.Add((int)n.ToInt64()); }
                else { groups.Add(Marshal.PtrToStringUni(n)); }
                return true;
            }, IntPtr.Zero);
            if (groups.Count == 0) { return null; }

            object group;
            if (index >= 0)
            {
                if (index >= groups.Count) { return null; }
                group = groups[index];
            }
            else
            {
                if (!groups.Contains(-index)) { return null; }
                group = -index;
            }

            byte[] dir = ReadResource(module, group, 14);
            if (dir == null || dir.Length < 6) { return null; }
            int count = BitConverter.ToUInt16(dir, 4);
            int bestId = -1, bestWidth = -1, bestBits = -1;
            for (int i = 0; i < count; i++)
            {
                int o = 6 + 14 * i;
                if (o + 14 > dir.Length) { break; }
                int width = dir[o] == 0 ? 256 : dir[o];
                int bits = BitConverter.ToUInt16(dir, o + 6);
                if (width > bestWidth || (width == bestWidth && bits > bestBits))
                {
                    bestWidth = width; bestBits = bits; bestId = BitConverter.ToUInt16(dir, o + 12);
                }
            }
            if (bestId < 0) { return null; }
            return ReadResource(module, bestId, 3);
        }
        finally
        {
            FreeLibrary(module);
        }
    }
}
'@
    }

    # True when the bytes start with the PNG signature
    function Test-PngData {
        param([byte[]]$Data)
        $Data.Length -ge 24 -and $Data[0] -eq 0x89 -and $Data[1] -eq 0x50 -and $Data[2] -eq 0x4E -and $Data[3] -eq 0x47
    }

    # Image data of the largest frame of an .ico file; $null when the file is not a valid icon
    function Get-LargestIcoFrame {
        param([byte[]]$Bytes)
        if ($Bytes.Length -lt 22 -or [BitConverter]::ToUInt16($Bytes, 2) -ne 1) { return $null }
        $count = [BitConverter]::ToUInt16($Bytes, 4)
        $best = $null
        for ($i = 0; $i -lt $count; $i++) {
            $o = 6 + 16 * $i
            if ($o + 16 -gt $Bytes.Length) { break }
            $width = if ($Bytes[$o] -eq 0) { 256 } else { [int]$Bytes[$o] }
            $bits = [BitConverter]::ToUInt16($Bytes, $o + 6)
            if (-not $best -or $width -gt $best.Width -or ($width -eq $best.Width -and $bits -gt $best.Bits)) {
                $best = @{ Width = $width; Bits = $bits; Size = [BitConverter]::ToUInt32($Bytes, $o + 8); Offset = [BitConverter]::ToUInt32($Bytes, $o + 12) }
            }
        }
        if (-not $best -or $best.Offset + $best.Size -gt $Bytes.Length) { return $null }
        $frame = [byte[]]::new($best.Size)
        [Array]::Copy($Bytes, $best.Offset, $frame, 0, $best.Size)
        , $frame
    }

    # Decodes icon image data (PNG, or a BMP DIB without file header) to a bitmap
    function ConvertFrom-IconData {
        param([byte[]]$Data)
        if (Test-PngData $Data) {
            $stream = [System.IO.MemoryStream]::new($Data)
            try {
                $image = [System.Drawing.Image]::FromStream($stream)
                try { return [System.Drawing.Bitmap]::new($image) } finally { $image.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        # Wrap the DIB in a one-entry .ico so System.Drawing can decode it; the DIB height covers the
        # XOR and AND masks, so the icon height is half of it
        $width = [BitConverter]::ToInt32($Data, 4)
        $height = [int]([Math]::Abs([BitConverter]::ToInt32($Data, 8)) / 2)
        $bits = [BitConverter]::ToUInt16($Data, 14)
        $stream = [System.IO.MemoryStream]::new()
        $writer = [System.IO.BinaryWriter]::new($stream)
        try {
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
            $writer.Write([byte]($width % 256)); $writer.Write([byte]($height % 256)); $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]$bits); $writer.Write([uint32]$Data.Length); $writer.Write([uint32]22)
            $writer.Write($Data)
            $writer.Flush()
            [void]$stream.Seek(0, [System.IO.SeekOrigin]::Begin)
            $icon = [System.Drawing.Icon]::new($stream, $width, $height)
            try { return $icon.ToBitmap() } finally { $icon.Dispose() }
        }
        finally { $writer.Dispose(); $stream.Dispose() }
    }

    # High-quality downscale to fit MaxSize; returns the same bitmap when it already fits
    function Resize-IconBitmap {
        param([System.Drawing.Bitmap]$Bitmap, [int]$Limit)
        if ($Bitmap.Width -le $Limit -and $Bitmap.Height -le $Limit) { return $Bitmap }
        $scale = $Limit / [double][Math]::Max($Bitmap.Width, $Bitmap.Height)
        $width = [Math]::Max(1, [int][Math]::Round($Bitmap.Width * $scale))
        $height = [Math]::Max(1, [int][Math]::Round($Bitmap.Height * $scale))
        $resized = [System.Drawing.Bitmap]::new($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($resized)
        $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $graphics.DrawImage($Bitmap, [System.Drawing.Rectangle]::new(0, 0, $width, $height), 0, 0, $Bitmap.Width, $Bitmap.Height, [System.Drawing.GraphicsUnit]::Pixel, $attributes)
        }
        finally { $attributes.Dispose(); $graphics.Dispose(); $Bitmap.Dispose() }
        $resized
    }

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
    $bitmap = $null
    try {
        $data = $null
        switch ($file.Extension.ToLowerInvariant()) {
            { $_ -in '.exe', '.dll' } { $data = [ExportAppIconNative]::GetBestIcon($file.FullName, $Index) }
            '.ico' { $data = Get-LargestIcoFrame -Bytes ([System.IO.File]::ReadAllBytes($file.FullName)) }
            { $_ -in '.png', '.jpg', '.jpeg', '.bmp', '.gif' } {
                $stream = [System.IO.MemoryStream]::new([System.IO.File]::ReadAllBytes($file.FullName))
                try {
                    $image = [System.Drawing.Image]::FromStream($stream)
                    try { $bitmap = [System.Drawing.Bitmap]::new($image) } finally { $image.Dispose() }
                }
                finally { $stream.Dispose() }
            }
        }

        if ($data) {
            if ((Test-PngData $data) -and $Format -eq 'png') {
                # Width and height are big-endian at offsets 16 and 20 of the PNG header
                $pngWidth = ([int]$data[16] -shl 24) + ([int]$data[17] -shl 16) + ([int]$data[18] -shl 8) + $data[19]
                $pngHeight = ([int]$data[20] -shl 24) + ([int]$data[21] -shl 16) + ([int]$data[22] -shl 8) + $data[23]
                if ($pngWidth -le $MaxSize -and $pngHeight -le $MaxSize) {
                    [System.IO.File]::WriteAllBytes($out, $data)
                    return Get-Item -LiteralPath $out | Add-Member -NotePropertyName IconWidth -NotePropertyValue $pngWidth -PassThru |
                        Add-Member -NotePropertyName IconHeight -NotePropertyValue $pngHeight -PassThru
                }
            }
            $bitmap = ConvertFrom-IconData -Data $data
        }
    }
    catch {
        Write-Verbose "Could not read the icon resources of '$($file.FullName)': $($_.Exception.Message)"
        if ($bitmap) { $bitmap.Dispose() }
        $bitmap = $null
    }

    if (-not $bitmap) {
        # No icon resources: the shell's associated icon (32 px)
        $icon = $null
        try { $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($file.FullName) }
        catch { Write-Verbose "ExtractAssociatedIcon failed: $($_.Exception.Message)" }
        if (-not $icon) {
            Write-Warning "No associated icon image found in $($file.FullName)"
            return
        }
        try { $bitmap = $icon.ToBitmap() } finally { $icon.Dispose() }
    }

    try {
        $bitmap = Resize-IconBitmap -Bitmap $bitmap -Limit $MaxSize
        $width = $bitmap.Width
        $height = $bitmap.Height
        $bitmap.Save($out, $imageFormat)
    }
    finally {
        $bitmap.Dispose()
    }

    Get-Item -LiteralPath $out | Add-Member -NotePropertyName IconWidth -NotePropertyValue $width -PassThru |
        Add-Member -NotePropertyName IconHeight -NotePropertyValue $height -PassThru
}
