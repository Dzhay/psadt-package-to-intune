function Publish-PSADTIntuneApp {
    <#
    .SYNOPSIS
        Packages a PSADT v4 application and uploads it to Microsoft Intune.

    .DESCRIPTION
        Takes a working directory containing a PSADT v4 package, creates an .intunewin
        package, and uploads the application to Microsoft Intune as a new Win32 app,
        updates an existing one, or creates a new app that supersedes an existing one.

        App name, version, vendor and install context are read from the $adtSession
        block in Invoke-AppDeployToolkit.ps1. Detection rules are picked in a grid from
        MSI product codes found under Files\ and from recent Start Menu shortcuts on this
        machine (so install the app locally first).

        With -Install (-i) or -Uninstall (-u), the package is instead installed or
        uninstalled on this computer with the configured InstallCommandLine or
        UninstallCommandLine, run in the PSADT folder like Intune does. Nothing is
        packaged or uploaded. Install before packaging so the app's Start Menu shortcuts
        exist for the detection rules.

        Settings (tenant, app registration, owner, assignment group, scope tags, ...) come
        from the config file. Run Set-PSADTIntuneConfig once to create it, or see
        Get-Help about_PSADTIntune for details.

        Aliases: packageIntune, PSADTIntune

    .PARAMETER WorkingDirectory
        The directory containing the PSADT package folder, or the PSADT folder itself.
        Defaults to the current directory.

    .PARAMETER AppId
        The ID of an existing Intune Win32 app to update. The new .intunewin replaces the
        app's package content and the app version is set to the PSADT AppVersion.
        Detection rules, assignments and other settings are not changed.
        Mutually exclusive with -Supersede.

    .PARAMETER Supersede
        The ID of an existing Intune Win32 app to supersede. Creates a new app that
        inherits the old app's display name and description, configures Update
        supersedence over it, and copies its group assignments as exclusions. The
        configured AADGroupId is assigned as Available (Include) for testing.
        Mutually exclusive with -AppId.

    .PARAMETER Install
        Installs the package on this computer with the configured InstallCommandLine
        (default: Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto).
        Shows a UAC prompt when the package has RequireAdmin = $true and PowerShell is not
        elevated. Exit codes 0, 1641 and 3010 count as success. Does not need TenantId or
        ClientId, and works without a config file (defaults are used). Alias: -i

    .PARAMETER Uninstall
        Uninstalls the package from this computer with the configured UninstallCommandLine
        (default: Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto).
        Works like -Install. Alias: -u

    .PARAMETER ConfigPath
        Path to a config file to use instead of the default
        (%APPDATA%\PSADTIntune\intune-config.json or $env:PSADTINTUNE_CONFIG).

    .PARAMETER Help
        Shows a short quick-start, the commands, and which config file is in use, then exits.

    .EXAMPLE
        packageIntune
        Packages the PSADT app in the current directory and creates a new Intune app.

    .EXAMPLE
        packageIntune -WorkingDirectory 'C:\Packages\Contoso_Example_App'
        Runs against a specific directory and creates a new Intune app.

    .EXAMPLE
        packageIntune -AppId 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        Packages the current directory and replaces the package of an existing Intune app.

    .EXAMPLE
        packageIntune -Supersede 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        Creates a new app that supersedes the specified app and excludes its assigned groups.

    .EXAMPLE
        packageIntune -i
        Installs the PSADT package in the current directory on this computer, for example
        before packaging so its Start Menu shortcut can be picked as detection rule.

    .EXAMPLE
        packageIntune -u
        Uninstalls the PSADT package in the current directory from this computer.

    .EXAMPLE
        packageIntune -ConfigPath '\\server\share\intune-config.json'
        Uses a shared config file instead of the per-user one.

    .EXAMPLE
        packageIntune -WhatIf
        Builds the package and shows the parameters that would be uploaded, without changing Intune.

    .EXAMPLE
        packageIntune -Help
        Shows the quick-start and the config file in use.

    .LINK
        about_PSADTIntune

    .LINK
        Set-PSADTIntuneConfig

    .LINK
        https://github.com/Dzhay/psadt-package-to-intune
    #>
    [CmdletBinding(DefaultParameterSetName = 'New', SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'ShouldProcess is handled by the private functions that change Intune or this computer.')]
    [Alias('packageIntune', 'PSADTIntune')]
    param(
        [Parameter(ParameterSetName = 'New', Position = 0)]
        [Parameter(ParameterSetName = 'Update', Position = 0)]
        [Parameter(ParameterSetName = 'Supersede', Position = 0)]
        [Parameter(ParameterSetName = 'Install', Position = 0)]
        [Parameter(ParameterSetName = 'Uninstall', Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$WorkingDirectory = $PWD.ProviderPath,

        [Parameter(Mandatory, ParameterSetName = 'Update')]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$AppId,

        [Parameter(Mandatory, ParameterSetName = 'Supersede')]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$Supersede,

        [Parameter(Mandatory, ParameterSetName = 'Install')]
        [Alias('i')]
        [switch]$Install,

        [Parameter(Mandatory, ParameterSetName = 'Uninstall')]
        [Alias('u')]
        [switch]$Uninstall,

        [Parameter(ParameterSetName = 'New')]
        [Parameter(ParameterSetName = 'Update')]
        [Parameter(ParameterSetName = 'Supersede')]
        [Parameter(ParameterSetName = 'Install')]
        [Parameter(ParameterSetName = 'Uninstall')]
        [Parameter(ParameterSetName = 'Help')]
        [string]$ConfigPath,

        [Parameter(Mandatory, ParameterSetName = 'Help')]
        [switch]$Help
    )

    if ($Help) {
        Show-PSADTIntuneQuickHelp -ConfigPath $ConfigPath
        return
    }

    if ($Install -or $Uninstall) {
        # Only the command lines are needed; without a config file the defaults apply,
        # but an explicitly given -ConfigPath must exist
        $config = Import-PSADTIntuneConfig -ConfigPath $ConfigPath -AllowMissing:(-not $ConfigPath)
        $package = Resolve-PSADTPackagePath -WorkingDirectory $WorkingDirectory
        $metadata = Get-PSADTAppInfo -ScriptPath $package.ScriptPath
        if ($Install) {
            $deploymentType = 'Install'
            $commandLine = $config.Params.InstallCommandLine
        }
        else {
            $deploymentType = 'Uninstall'
            $commandLine = $config.Params.UninstallCommandLine
        }
        Invoke-PSADTDeployment -DeploymentType $deploymentType -PSADTDirectory $package.PSADTDirectory -CommandLine $commandLine -Metadata $metadata
        return
    }

    $config = Import-PSADTIntuneConfig -ConfigPath $ConfigPath -RequireConnectionSettings
    $package = Resolve-PSADTPackagePath -WorkingDirectory $WorkingDirectory
    $WorkingDirectory = $package.WorkingDirectory
    $PSADTDirectoryPath = $package.PSADTDirectory
    $PSADTExeName = 'Invoke-AppDeployToolkit.exe'

    Push-Location -LiteralPath $WorkingDirectory
    try {
        Write-Host "Working in directory: $WorkingDirectory"
        Write-Host "PSADT directory: $PSADTDirectoryPath"

        $metadata = Get-PSADTAppInfo -ScriptPath $package.ScriptPath

        # Create .intunewin package
        $intunewinFilePath = Get-IntuneWinPath -WorkingDirectory $WorkingDirectory -PSADTDirectoryPath $PSADTDirectoryPath -PSADTExeName $PSADTExeName -FolderName $package.FolderName
        Write-Host "IntuneWin file: $intunewinFilePath"

        $Paths = @{
            'PSADTScriptFile'  = $package.ScriptPath
            'WorkingDirectory' = $WorkingDirectory
            'intunewinFile'    = $intunewinFilePath
            'PSADTDirectory'   = $PSADTDirectoryPath
        }

        # Route to upload or update
        if ($PSCmdlet.ParameterSetName -eq 'Update') {
            Update-ExistingIntuneApp -AppId $AppId -Paths $Paths -Config $config -Metadata $metadata
        }
        else {
            $newApp = Invoke-IntuneUpload -Paths $Paths -Config $config -Metadata $metadata
            if ($Supersede) {
                if (-not $newApp) {
                    Write-Warning "Supersedence over '$Supersede' was not configured because no app was uploaded."
                }
                else {
                    $newAppIdStr = @($newApp.id) | Where-Object { $_ -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' } | Select-Object -First 1
                    if (-not $newAppIdStr) {
                        throw "Could not extract a valid app ID from the upload response. Raw value: $($newApp.id)"
                    }
                    Set-IntuneAppSupersedence -NewAppId $newAppIdStr -OldAppId $Supersede -Config $config
                }
            }
        }

        # Cleanup if working directory is the PSADT directory (keep the package folder clean)
        if ($WorkingDirectory -eq $PSADTDirectoryPath) {
            Get-ChildItem -LiteralPath $WorkingDirectory -Filter '*.intunewin' | Remove-Item -Force -WhatIf:$false -Confirm:$false
            Get-ChildItem -LiteralPath $WorkingDirectory -Filter 'AppIcon.png' | Remove-Item -Force -WhatIf:$false -Confirm:$false
            Write-Host "Removed IntuneWin and AppIcon files from $WorkingDirectory" -ForegroundColor Green
        }
    }
    finally {
        Pop-Location
    }
}
