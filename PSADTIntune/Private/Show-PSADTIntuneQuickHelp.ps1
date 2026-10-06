function Show-PSADTIntuneQuickHelp {
    <#
    .SYNOPSIS
        Prints the quick-start shown by `packageIntune -Help`, including config status.
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath
    )

    $location = Resolve-PSADTIntuneConfigPath -ConfigPath $ConfigPath
    $module = $MyInvocation.MyCommand.Module

    Write-Host ""
    Write-Host "PSADTIntune $($module.Version) - package PSADT v4 apps and upload them to Intune" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor Yellow
    Write-Host "  packageIntune [-WorkingDirectory <path>]       Create a new Win32 app"
    Write-Host "  packageIntune -AppId <guid>                    Replace the package of an existing app"
    Write-Host "  packageIntune -Supersede <guid>                Create a new app that supersedes an existing one"
    Write-Host "  packageIntune -Install   (-i)                  Install the package on this computer (InstallCommandLine)"
    Write-Host "  packageIntune -Uninstall (-u)                  Uninstall it from this computer (UninstallCommandLine)"
    Write-Host "  Common options: -ConfigPath <file>  -WhatIf  -Confirm:`$false"
    Write-Host "  PSADTIntune works the same as packageIntune (both run Publish-PSADTIntuneApp)."
    Write-Host ""
    Write-Host "FOLDER LAYOUT" -ForegroundColor Yellow
    Write-Host "  Run in a folder that contains the PSADT package folder, or in the PSADT folder itself:"
    Write-Host "    Contoso_Example_App\"
    Write-Host "    +-- Contoso_Example_App_Package\   (Invoke-AppDeployToolkit.ps1/.exe, Files\, ...)"
    Write-Host ""
    Write-Host "CONFIG" -ForegroundColor Yellow
    Write-Host "  Set-PSADTIntuneConfig -TenantId 'contoso.onmicrosoft.com' -ClientId '<client-id>'"
    Write-Host "  Set-PSADTIntuneConfig -AADGroupId '<group-id>' -Owner 'IT'   # optional settings"
    Write-Host "  Get-PSADTIntuneConfig                                        # show effective settings"
    Write-Host ""
    if ($location.Exists) {
        Write-Host "  Config in use: $($location.Path)" -ForegroundColor Green
    }
    else {
        Write-Host "  No config found at: $($location.Path)" -ForegroundColor Red
        Write-Host "  Run Set-PSADTIntuneConfig to create it." -ForegroundColor Red
    }
    Write-Host "  Source       : $($location.Source)"
    Write-Host ""
    Write-Host "MORE HELP" -ForegroundColor Yellow
    Write-Host "  Get-Help about_PSADTIntune        Full guide: setup, config keys, permissions, troubleshooting"
    Write-Host "  Get-Help packageIntune -Examples  Usage examples"
    Write-Host "  Get-Help Set-PSADTIntuneConfig -Full"
    Write-Host ""
}
