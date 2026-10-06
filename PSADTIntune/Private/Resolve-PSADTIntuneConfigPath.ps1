function Resolve-PSADTIntuneConfigPath {
    <#
    .SYNOPSIS
        Determines which config file to use.
    .DESCRIPTION
        Resolution order (first match wins):
          1. -ConfigPath parameter
          2. $env:PSADTINTUNE_CONFIG
          3. %APPDATA%\PSADTIntune\intune-config.json
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$ConfigPath
    )

    if ($ConfigPath) {
        $path = $ConfigPath
        $source = 'Parameter -ConfigPath'
    }
    elseif ($env:PSADTINTUNE_CONFIG) {
        $path = $env:PSADTINTUNE_CONFIG
        $source = 'Environment variable PSADTINTUNE_CONFIG'
    }
    else {
        $path = Join-Path -Path $env:APPDATA -ChildPath 'PSADTIntune\intune-config.json'
        $source = 'User profile (default)'
    }

    [PSCustomObject]@{
        Path   = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        Source = $source
        Exists = Test-Path -LiteralPath $path -PathType Leaf
    }
}
