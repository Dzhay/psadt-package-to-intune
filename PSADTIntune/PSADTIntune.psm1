# Path to the shipped config template; also provides defaults for missing keys
$script:DefaultConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'intune-config.json'

$Private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$Public = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($Private + $Public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import '$($file.FullName)': $_"
    }
}

Export-ModuleMember -Function $Public.BaseName -Alias 'packageIntune', 'PSADTIntune'
