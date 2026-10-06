function Test-PSADTIntuneConfigValue {
    <#
    .SYNOPSIS
        Returns $true when a config value counts as "set" (not null, empty string or empty array).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return -not [string]::IsNullOrWhiteSpace($Value) }
    if ($Value -is [System.Collections.IEnumerable]) { return @($Value).Count -gt 0 }
    return $true
}

function Merge-PSADTIntuneConfig {
    <#
    .SYNOPSIS
        Recursively overlays a user config on top of the default config.
    .DESCRIPTION
        Values that are not set in the override (null, empty string, empty array)
        keep the default, so older config files keep working when new keys are added.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Base,

        [AllowNull()]
        $Override
    )

    $result = [ordered]@{}
    foreach ($property in $Base.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    if ($null -ne $Override) {
        foreach ($property in $Override.PSObject.Properties) {
            $baseValue = $result[$property.Name]
            if ($baseValue -is [System.Management.Automation.PSCustomObject] -and
                $property.Value -is [System.Management.Automation.PSCustomObject]) {
                $result[$property.Name] = Merge-PSADTIntuneConfig -Base $baseValue -Override $property.Value
            }
            elseif (Test-PSADTIntuneConfigValue -Value $property.Value) {
                $result[$property.Name] = $property.Value
            }
            elseif (-not $result.Contains($property.Name)) {
                $result[$property.Name] = $property.Value
            }
        }
    }

    [PSCustomObject]$result
}
