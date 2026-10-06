function Get-PSADTIntuneConfig {
    <#
    .SYNOPSIS
        Shows the effective PSADTIntune configuration and which file it comes from.

    .DESCRIPTION
        Resolves the config file (-ConfigPath, then $env:PSADTINTUNE_CONFIG, then
        %APPDATA%\PSADTIntune\intune-config.json), merges it over the module defaults
        and returns the result. Works even when no config file exists yet, so you can
        see the defaults.

    .PARAMETER ConfigPath
        Read this file instead of the default location.

    .EXAMPLE
        Get-PSADTIntuneConfig
        Shows the settings packageIntune will use.

    .EXAMPLE
        (Get-PSADTIntuneConfig).ConfigPath | Split-Path | Invoke-Item
        Opens the folder containing the config file.

    .LINK
        Set-PSADTIntuneConfig

    .LINK
        about_PSADTIntune
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ConfigPath
    )

    $location = Resolve-PSADTIntuneConfigPath -ConfigPath $ConfigPath
    $config = Import-PSADTIntuneConfig -ConfigPath $location.Path -AllowMissing

    [PSCustomObject]@{
        ConfigPath            = $location.Path
        ConfigSource          = $location.Source
        ConfigExists          = $location.Exists
        TenantId              = $config.TenantId
        AADClientId           = $config.AADClientId
        Owner                 = $config.Params.Owner
        AADGroupId            = $config.Params.AADGroupId
        ScopeTagNameArray     = @($config.Params.ScopeTagNameArray)
        Architecture          = $config.Params.Architecture
        MinimumWindowsRelease = $config.Params.MinimumWindowsRelease
        InstallCommandLine    = $config.Params.InstallCommandLine
        UninstallCommandLine  = $config.Params.UninstallCommandLine
    }
}
