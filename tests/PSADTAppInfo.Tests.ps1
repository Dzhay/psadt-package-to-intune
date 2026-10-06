BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifest -Force

    function Get-TestAppInfo {
        # Writes the script content to a file and parses it with the module's private Get-PSADTAppInfo
        param([Parameter(Mandatory)][string]$Content)

        $path = Join-Path $TestDrive "Invoke-AppDeployToolkit-$([guid]::NewGuid()).ps1"
        Set-Content -LiteralPath $path -Value $Content
        InModuleScope PSADTIntune -Parameters @{ Path = $path } {
            param($Path)
            Get-PSADTAppInfo -ScriptPath $Path
        }
    }
}

Describe 'Get-PSADTAppInfo' {
    BeforeAll {
        Mock Write-Warning -ModuleName PSADTIntune {}
    }

    It 'reads the app details from the PSADT v4 $adtSession block' {
        # Layout of the PSADT v4 template, including keys that contain "AppVersion"/"AppName"
        $info = Get-TestAppInfo -Content @'
$adtSession = @{
    # App variables.
    AppVendor = 'Contoso'
    AppName = 'Example App'
    AppVersion = '1.2.3'
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppScriptVersion = '1.0.0'
    AppScriptAuthor = 'Packaging Team'
    RequireAdmin = $true

    # Install Titles (Only set here to override defaults set by the toolkit).
    InstallName = 'Contoso Example App Installer'
    InstallTitle = ''
}
'@

        $info.AppName | Should -Be 'Example App'
        $info.AppVersion | Should -Be '1.2.3'
        $info.AppVendor | Should -Be 'Contoso'
        $info.RequireAdmin | Should -BeTrue
        $info.Context | Should -Be 'system'
    }

    It 'ignores commented-out lines' {
        $info = Get-TestAppInfo -Content @'
$adtSession = @{
    # AppName = 'Old Name'
    #AppVersion = '0.0.1'
    AppName = 'New Name'
    AppVersion = '2.0.0'
}
'@

        $info.AppName | Should -Be 'New Name'
        $info.AppVersion | Should -Be '2.0.0'
    }

    It 'supports double-quoted values' {
        $info = Get-TestAppInfo -Content @'
$adtSession = @{
    AppVendor = "Contoso"
    AppName = "Example App"
    AppVersion = "3.1"
}
'@

        $info.AppName | Should -Be 'Example App'
        $info.AppVersion | Should -Be '3.1'
        $info.AppVendor | Should -Be 'Contoso'
    }

    It 'uses the user context when RequireAdmin is $false' {
        $info = Get-TestAppInfo -Content @'
$adtSession = @{
    AppName = 'Example App'
    AppVersion = '1.0'
    RequireAdmin = $false
}
'@

        $info.RequireAdmin | Should -BeFalse
        $info.Context | Should -Be 'user'
    }

    It 'uses Unknown when the vendor is empty' {
        $info = Get-TestAppInfo -Content @'
$adtSession = @{
    AppVendor = ''
    AppName = 'Example App'
    AppVersion = '1.0'
    RequireAdmin = $true
}
'@

        $info.AppVendor | Should -Be 'Unknown'
    }

    It 'defaults to the system context with a warning when RequireAdmin is missing' {
        $info = Get-TestAppInfo -Content @'
$adtSession = @{
    AppName = 'Example App'
    AppVersion = '1.0'
}
'@

        $info.Context | Should -Be 'system'
        Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like '*RequireAdmin*' }
    }

    It 'throws when AppName is empty, as in the unedited PSADT template' {
        {
            Get-TestAppInfo -Content @'
$adtSession = @{
    AppName = ''
    AppVersion = '1.0'
}
'@
        } | Should -Throw '*Could not extract AppName*'
    }

    It 'throws when AppVersion is missing' {
        {
            Get-TestAppInfo -Content @'
$adtSession = @{
    AppName = 'Example App'
}
'@
        } | Should -Throw '*Could not extract AppVersion*'
    }
}
