function Invoke-IntuneWinPackageBuild {
    <#
    .SYNOPSIS
        Creates a .intunewin package from the PSADT folder and names it after the package folder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$PSADTDirectoryPath,
        [Parameter(Mandatory)][string]$PSADTExeName,
        [Parameter(Mandatory)][string]$FolderName
    )

    try {
        Write-Warning "Creating new .intunewin file..."
        $null = New-IntuneWin32AppPackage -SourceFolder $PSADTDirectoryPath -SetupFile $PSADTExeName -OutputFolder $WorkingDirectory
        $newFile = Get-ChildItem -LiteralPath $WorkingDirectory -Filter '*.intunewin' |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $newFile) {
            throw "New-IntuneWin32AppPackage did not produce a .intunewin file in '$WorkingDirectory'."
        }
        $targetName = "$FolderName.intunewin"
        if ($newFile.Name -ne $targetName) {
            Rename-Item -LiteralPath $newFile.FullName -NewName $targetName -ErrorAction Stop -WhatIf:$false -Confirm:$false
        }
        return Join-Path -Path $WorkingDirectory -ChildPath $targetName
    }
    catch {
        throw "Error creating .intunewin file: $_"
    }
}
