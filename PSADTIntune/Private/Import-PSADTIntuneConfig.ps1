function Read-PSADTIntuneConfigFile {
    <#
    .SYNOPSIS
        Reads a JSON config file and returns it as an object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Config file '$Path' could not be read as JSON: $($_.Exception.Message)"
    }
}

function Import-PSADTIntuneConfig {
    <#
    .SYNOPSIS
        Loads the effective configuration: the user config merged over the shipped defaults.
    .PARAMETER ConfigPath
        Optional explicit config file path.
    .PARAMETER AllowMissing
        Return defaults instead of throwing when no user config exists.
    .PARAMETER RequireConnectionSettings
        Throw when TenantId or AADClientId are not set.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ConfigPath,
        [switch]$AllowMissing,
        [switch]$RequireConnectionSettings
    )

    $location = Resolve-PSADTIntuneConfigPath -ConfigPath $ConfigPath
    $defaults = Read-PSADTIntuneConfigFile -Path $script:DefaultConfigPath

    $userConfig = $null
    if ($location.Exists) {
        $userConfig = Read-PSADTIntuneConfigFile -Path $location.Path
    }
    elseif (-not $AllowMissing) {
        throw ("No PSADTIntune config found at '$($location.Path)' ($($location.Source)).`n" +
            "Create one with: Set-PSADTIntuneConfig -TenantId 'contoso.onmicrosoft.com' -ClientId '<app-registration-client-id>'`n" +
            "See: packageIntune -Help")
    }

    $config = Merge-PSADTIntuneConfig -Base $defaults -Override $userConfig

    if ($RequireConnectionSettings) {
        $missing = @('TenantId', 'AADClientId') | Where-Object { -not (Test-PSADTIntuneConfigValue -Value $config.$_) }
        if ($missing) {
            throw ("Config '$($location.Path)' is missing: $($missing -join ', ').`n" +
                "Set them with: Set-PSADTIntuneConfig -TenantId '<tenant>' -ClientId '<client-id>'")
        }
    }

    $config
}
