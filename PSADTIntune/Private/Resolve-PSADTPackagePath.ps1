function Resolve-PSADTPackagePath {
    <#
    .SYNOPSIS
        Finds the PSADT v4 package for a working directory.
    .DESCRIPTION
        The package is the only subfolder of the working directory, or the working
        directory itself when it has several subfolders (Files\, Assets\, ...).
        Throws when no package or no Invoke-AppDeployToolkit.ps1 is found.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$WorkingDirectory
    )

    # Normalize to a full path without trailing separator (".", relative paths, "C:\pkg\")
    $WorkingDirectory = Convert-Path -LiteralPath $WorkingDirectory
    if ($WorkingDirectory.Length -gt 3) {
        $WorkingDirectory = $WorkingDirectory.TrimEnd('\', '/')
    }

    $folders = @(Get-ChildItem -LiteralPath $WorkingDirectory -Directory)
    if ($folders.Count -eq 1) {
        $psadtDirectory = $folders[0].FullName
        $folderName = $folders[0].Name
    }
    elseif ($folders.Count -gt 1) {
        $psadtDirectory = $WorkingDirectory
        $folderName = Split-Path -Path $WorkingDirectory -Leaf
    }
    else {
        throw "No subdirectory found in '$WorkingDirectory'. Please ensure the PSADT files exist. See: packageIntune -Help"
    }

    $scriptPath = Join-Path -Path $psadtDirectory -ChildPath 'Invoke-AppDeployToolkit.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "No PSADT v4 script (Invoke-AppDeployToolkit.ps1) found in '$psadtDirectory'. See: packageIntune -Help"
    }

    [PSCustomObject]@{
        WorkingDirectory = $WorkingDirectory
        PSADTDirectory   = $psadtDirectory
        FolderName       = $folderName
        ScriptPath       = $scriptPath
    }
}
