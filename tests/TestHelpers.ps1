# Shared paths and fixtures for the Pester tests. Dot-source from a BeforeAll block:
#   BeforeAll { . (Join-Path $PSScriptRoot 'TestHelpers.ps1') }

$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$ModuleRoot = Join-Path -Path $RepoRoot -ChildPath 'PSADTIntune'
$ModuleManifest = Join-Path -Path $ModuleRoot -ChildPath 'PSADTIntune.psd1'

$TestTenantId = 'contoso.onmicrosoft.com'
$TestClientId = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
$TestGroupId = '11111111-2222-3333-4444-555555555555'

function New-TestPSADTPackage {
    <#
    .SYNOPSIS
        Creates <Path>\Contoso_Test_App\Contoso_Test_App_Package with a minimal PSADT v4 layout.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$AppName = 'Test App',
        [string]$AppVersion = '9.9.9',
        [string]$AppVendor = 'Contoso',
        [string]$RequireAdmin = '$true'
    )

    $appDirectory = Join-Path -Path $Path -ChildPath 'Contoso_Test_App'
    $packageDirectory = Join-Path -Path $appDirectory -ChildPath 'Contoso_Test_App_Package'
    New-Item -ItemType Directory -Path (Join-Path $packageDirectory 'Files'), (Join-Path $packageDirectory 'Assets') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $packageDirectory 'Invoke-AppDeployToolkit.exe') -Value 'stub'
    @"
`$adtSession = @{
    AppVendor = '$AppVendor'
    AppName = '$AppName'
    AppVersion = '$AppVersion'
    RequireAdmin = $RequireAdmin
}
"@ | Set-Content -LiteralPath (Join-Path $packageDirectory 'Invoke-AppDeployToolkit.ps1')

    [PSCustomObject]@{
        AppDirectory     = $appDirectory
        PackageDirectory = $packageDirectory
    }
}

function New-TestConfig {
    <#
    .SYNOPSIS
        Writes a config file with the test tenant/client and the given Params; returns its path.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [hashtable]$Params = @{}
    )

    New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force | Out-Null
    [ordered]@{
        TenantId    = $TestTenantId
        AADClientId = $TestClientId
        Params      = $Params
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path
    $Path
}

function New-TestPng {
    <#
    .SYNOPSIS
        Writes a 1x1 PNG image; returns its path.
    #>
    param(
        [Parameter(Mandatory)][string]$Path
    )

    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::new(1, 1)
    try {
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $bitmap.Dispose()
    }
    $Path
}
