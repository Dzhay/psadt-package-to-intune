function Get-IntuneWinPath {
    <#
    .SYNOPSIS
        Returns the .intunewin file to upload, reusing an existing one or building a new one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$PSADTDirectoryPath,
        [Parameter(Mandatory)][string]$PSADTExeName,
        [Parameter(Mandatory)][string]$FolderName
    )

    $buildParams = @{
        WorkingDirectory   = $WorkingDirectory
        PSADTDirectoryPath = $PSADTDirectoryPath
        PSADTExeName       = $PSADTExeName
        FolderName         = $FolderName
    }

    $existingIntunewin = @(Get-ChildItem -LiteralPath $WorkingDirectory -Filter '*.intunewin')
    # No existing .intunewin file found
    if ($existingIntunewin.Count -eq 0) {
        return Invoke-IntuneWinPackageBuild @buildParams
    }
    # Multiple existing .intunewin files found
    if ($existingIntunewin.Count -gt 1) {
        throw "Multiple .intunewin files found in '$WorkingDirectory'. Please ensure only one is present."
    }
    Write-Warning "An .intunewin file already exists. Do you want to keep it? (Y/N). Pressing Enter will create a new one."
    $response = Read-Host
    # User chose to keep the existing .intunewin file
    if ($response -match '^[Yy]') {
        return $existingIntunewin[0].FullName
    }
    # User chose to create a new .intunewin file
    try {
        # Local build step - runs even under -WhatIf / -Confirm (only Intune changes are gated)
        $existingIntunewin | Remove-Item -Force -ErrorAction Stop -WhatIf:$false -Confirm:$false
    }
    catch {
        throw "Failed to remove existing .intunewin file. Ensure it is not in use. Error: $_"
    }
    return Invoke-IntuneWinPackageBuild @buildParams
}
