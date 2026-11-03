BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifest -Force
}

Describe 'Get-PackageInfo' {
    BeforeAll {
        Mock Write-Warning -ModuleName PSADTIntune {}
    }

    BeforeEach {
        $folder = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid()))
        $infoPath = Join-Path $folder 'PackageInfo.json'
    }

    It 'returns $null without a warning when the file is missing' {
        $result = InModuleScope PSADTIntune -Parameters @{ Folder = $folder.FullName } { param($Folder) Get-PackageInfo -PackageDirectory $Folder }

        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 0 -Exactly
    }

    It 'returns $null and warns with the file name when the JSON is invalid' {
        Set-Content -LiteralPath $infoPath -Value '{ not json'

        $result = InModuleScope PSADTIntune -Parameters @{ Folder = $folder.FullName } { param($Folder) Get-PackageInfo -PackageDirectory $Folder }

        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like '*PackageInfo.json*' }
    }

    It 'returns the parsed object for valid JSON' {
        @{ SchemaVersion = 1; Kind = 'Msi'; Description = 'Store text'; Detection = @{ Type = 'File'; File = 'app.exe' } } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $infoPath

        $result = InModuleScope PSADTIntune -Parameters @{ Folder = $folder.FullName } { param($Folder) Get-PackageInfo -PackageDirectory $Folder }

        $result.Kind | Should -Be 'Msi'
        $result.Description | Should -Be 'Store text'
        $result.Detection.File | Should -Be 'app.exe'
        Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 0 -Exactly
    }
}
