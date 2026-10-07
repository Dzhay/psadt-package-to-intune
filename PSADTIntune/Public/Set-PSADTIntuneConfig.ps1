function Set-PSADTIntuneConfig {
    <#
    .SYNOPSIS
        Creates or updates the PSADTIntune config file.

    .DESCRIPTION
        Writes settings to the per-user config file
        (%APPDATA%\PSADTIntune\intune-config.json by default). Only the parameters you
        pass are changed; everything else in the file is kept. Settings that are not
        in the file fall back to the module defaults.

        The file lives outside the module folder, so it survives Update-Module.

        When TenantId or ClientId is not set yet, you are prompted for it if you are
        creating a new config file or run the command without parameters.

        To edit the file by hand instead, run packageIntune -Config.

        Settings:
          TenantId              Entra ID tenant, e.g. contoso.onmicrosoft.com or a tenant GUID (required)
          ClientId              App registration (client) ID used to sign in (required)
          Owner                 Owner shown on the Intune app                       default: (empty)
          AADGroupId            Group assigned as Available (Include) after upload  default: (none)
          ScopeTag              Intune scope tag names                              default: Default
          Architecture          Requirement rule architecture                       default: x64
          MinimumWindowsRelease Requirement rule minimum Windows release            default: W11_22H2
          InstallCommandLine    Install command                                     default: PSADT v4 Install, DeployMode Auto
          UninstallCommandLine  Uninstall command                                   default: PSADT v4 Uninstall, DeployMode Auto

        Pass an empty string ('') to clear a setting and fall back to its default.

    .PARAMETER TenantId
        Entra ID tenant name or ID, e.g. contoso.onmicrosoft.com.

    .PARAMETER ClientId
        Client (application) ID of the Entra ID app registration used to connect to Graph.

    .PARAMETER Owner
        Owner shown on the Intune app.

    .PARAMETER AADGroupId
        Object ID of an Entra ID group to assign as Available (Include) after upload.

    .PARAMETER ScopeTag
        One or more Intune scope tag names.

    .PARAMETER Architecture
        Requirement rule architecture, validated against New-IntuneWin32AppRequirementRule.
        IntuneWin32App 1.5.0 accepts: x64, x86, arm64, x64x86, AllWithARM64.

    .PARAMETER MinimumWindowsRelease
        Minimum supported Windows release, validated against New-IntuneWin32AppRequirementRule.
        IntuneWin32App 1.5.0 accepts W10_1607 ... W10_22H2, W11_21H2, W11_22H2.

    .PARAMETER InstallCommandLine
        Install command line for the Win32 app. Also used by packageIntune -Install (-i).

    .PARAMETER UninstallCommandLine
        Uninstall command line for the Win32 app. Also used by packageIntune -Uninstall (-u).

    .PARAMETER ConfigPath
        Write to this file instead of the default location.

    .PARAMETER PassThru
        Output the effective configuration after saving.

    .EXAMPLE
        Set-PSADTIntuneConfig -TenantId 'contoso.onmicrosoft.com' -ClientId 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
        First-time setup.

    .EXAMPLE
        Set-PSADTIntuneConfig
        First-time setup with prompts for TenantId and ClientId.

    .EXAMPLE
        Set-PSADTIntuneConfig -AADGroupId '11111111-2222-3333-4444-555555555555' -Owner 'Workplace Team' -ScopeTag 'Default', 'EMEA'
        Sets optional settings and keeps the rest.

    .EXAMPLE
        Set-PSADTIntuneConfig -AADGroupId ''
        Clears the assignment group so no assignment is made after upload.

    .LINK
        Get-PSADTIntuneConfig

    .LINK
        about_PSADTIntune
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$TenantId,

        [Alias('AADClientId')]
        [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$ClientId,

        [AllowEmptyString()]
        [string]$Owner,

        [AllowEmptyString()]
        [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string]$AADGroupId,

        [Alias('ScopeTagNameArray')]
        [AllowEmptyCollection()]
        [string[]]$ScopeTag,

        [AllowEmptyString()]
        [string]$Architecture,

        [AllowEmptyString()]
        [string]$MinimumWindowsRelease,

        [AllowEmptyString()]
        [string]$InstallCommandLine,

        [AllowEmptyString()]
        [string]$UninstallCommandLine,

        [string]$ConfigPath,

        [switch]$PassThru
    )

    # Validate requirement rule values against the installed IntuneWin32App, so typos fail now and not at upload
    $requirementParams = @{ Architecture = 'Architecture'; MinimumWindowsRelease = 'MinimumSupportedWindowsRelease' }
    $requirementCommand = Get-Command New-IntuneWin32AppRequirementRule -ErrorAction SilentlyContinue
    foreach ($name in $requirementParams.Keys) {
        $value = $PSBoundParameters[$name]
        if (-not $value -or -not $requirementCommand) { continue }
        $validValues = ($requirementCommand.Parameters[$requirementParams[$name]].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues
        if ($validValues -and $value -notin $validValues) {
            throw "Invalid -$name '$value'. Valid values: $($validValues -join ', ')"
        }
    }

    $location = Resolve-PSADTIntuneConfigPath -ConfigPath $ConfigPath

    # Parameter name -> config key (top level or under Params)
    $topLevelKeys = @{ TenantId = 'TenantId'; ClientId = 'AADClientId' }
    $paramsKeys = @{
        Owner                 = 'Owner'
        AADGroupId            = 'AADGroupId'
        ScopeTag              = 'ScopeTagNameArray'
        Architecture          = 'Architecture'
        MinimumWindowsRelease = 'MinimumWindowsRelease'
        InstallCommandLine    = 'InstallCommandLine'
        UninstallCommandLine  = 'UninstallCommandLine'
    }

    # Start from the existing file, or from the shipped template for a new one
    if ($location.Exists) {
        $config = Read-PSADTIntuneConfigFile -Path $location.Path
    }
    else {
        $config = Read-PSADTIntuneConfigFile -Path $script:DefaultConfigPath
    }

    # Prompt for unset connection settings when creating the file or when run without settings
    $settingPassed = $PSBoundParameters.Keys | Where-Object { $topLevelKeys.ContainsKey($_) -or $paramsKeys.ContainsKey($_) }
    if (-not $location.Exists -or -not $settingPassed) {
        # Prompted values go into new variables: the parameter variables keep their validation
        # attributes, which would reject bad input with a generic error before the check below
        if (-not $PSBoundParameters.ContainsKey('TenantId') -and -not (Test-PSADTIntuneConfigValue -Value $config.TenantId)) {
            $promptedTenantId = (Read-Host "TenantId (e.g. contoso.onmicrosoft.com)").Trim()
            if ($promptedTenantId) { $PSBoundParameters['TenantId'] = $promptedTenantId }
        }
        if (-not $PSBoundParameters.ContainsKey('ClientId') -and -not (Test-PSADTIntuneConfigValue -Value $config.AADClientId)) {
            $promptedClientId = (Read-Host "ClientId (app registration client ID)").Trim()
            if ($promptedClientId -and $promptedClientId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                throw "'$promptedClientId' is not a valid client ID (GUID). Nothing was saved."
            }
            if ($promptedClientId) { $PSBoundParameters['ClientId'] = $promptedClientId }
        }
    }
    if ($null -eq $config.PSObject.Properties['Params']) {
        $config | Add-Member -NotePropertyName 'Params' -NotePropertyValue ([PSCustomObject]@{})
    }

    $changed = @()
    foreach ($name in $topLevelKeys.Keys) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $config | Add-Member -NotePropertyName $topLevelKeys[$name] -NotePropertyValue $PSBoundParameters[$name] -Force
            $changed += $topLevelKeys[$name]
        }
    }
    foreach ($name in $paramsKeys.Keys) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $value = $PSBoundParameters[$name]
            if ($name -eq 'ScopeTag') { $value = @($value) }
            $config.Params | Add-Member -NotePropertyName $paramsKeys[$name] -NotePropertyValue $value -Force
            $changed += $paramsKeys[$name]
        }
    }

    if (-not $changed -and $location.Exists) {
        Write-Warning "No settings specified. Nothing changed in '$($location.Path)'. See: Get-Help Set-PSADTIntuneConfig -Full"
        return
    }

    $action = if ($location.Exists) { "Update $($changed -join ', ')" } else { 'Create config file' }
    if ($PSCmdlet.ShouldProcess($location.Path, $action)) {
        $directory = Split-Path -Path $location.Path -Parent
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $location.Path -Encoding utf8
        Write-Host "Saved config to $($location.Path)" -ForegroundColor Green

        $effective = Import-PSADTIntuneConfig -ConfigPath $location.Path
        $missing = @('TenantId', 'AADClientId') | Where-Object { -not (Test-PSADTIntuneConfigValue -Value $effective.$_) }
        if ($missing) {
            Write-Warning "Still missing: $($missing -join ', '). Set them before running packageIntune."
        }

        if ($PassThru) {
            Get-PSADTIntuneConfig -ConfigPath $location.Path
        }
    }
}
