function Open-PSADTIntuneConfigFile {
    <#
    .SYNOPSIS
        Opens the config file in an editor, creating it from the shipped template first if needed.
    .DESCRIPTION
        Uses $env:VISUAL or $env:EDITOR when it names a command, otherwise Notepad.
        Does not wait for the editor to close.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $directory = Split-Path -Path $Path -Parent
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force -WhatIf:$false -Confirm:$false | Out-Null
        }
        Copy-Item -LiteralPath $script:DefaultConfigPath -Destination $Path -WhatIf:$false -Confirm:$false
        Write-Host "Created $Path from the defaults." -ForegroundColor Green
    }

    $editor = @($env:VISUAL, $env:EDITOR) |
        Where-Object { $_ -and (Get-Command -Name $_ -CommandType Application -ErrorAction SilentlyContinue) } |
        Select-Object -First 1
    if (-not $editor -and $IsWindows) { $editor = 'notepad.exe' }

    if ($editor) {
        Start-Process -FilePath $editor -ArgumentList "`"$Path`""
    }
    else {
        Invoke-Item -LiteralPath $Path
    }

    Write-Host "Opened $Path"
    Write-Host "TenantId and AADClientId are required. All settings: Get-Help Set-PSADTIntuneConfig -Full"
}
