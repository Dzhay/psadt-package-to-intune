BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    Import-Module $ModuleManifest -Force

    $originalAppData = $env:APPDATA
    $originalConfigEnv = $env:PSADTINTUNE_CONFIG
}

AfterAll {
    $env:APPDATA = $originalAppData
    $env:PSADTINTUNE_CONFIG = $originalConfigEnv
}

Describe 'Config file location' {
    BeforeEach {
        $env:APPDATA = Join-Path $TestDrive ([guid]::NewGuid())
        $env:PSADTINTUNE_CONFIG = $null
    }

    It 'defaults to %APPDATA%\PSADTIntune\intune-config.json' {
        $config = Get-PSADTIntuneConfig

        $config.ConfigPath | Should -Be (Join-Path $env:APPDATA 'PSADTIntune\intune-config.json')
        $config.ConfigSource | Should -BeLike 'User profile*'
        $config.ConfigExists | Should -BeFalse
    }

    It 'uses $env:PSADTINTUNE_CONFIG over the default location' {
        $env:PSADTINTUNE_CONFIG = New-TestConfig -Path (Join-Path $TestDrive 'env.json')

        $config = Get-PSADTIntuneConfig

        $config.ConfigPath | Should -Be $env:PSADTINTUNE_CONFIG
        $config.ConfigSource | Should -BeLike 'Environment variable*'
        $config.ConfigExists | Should -BeTrue
    }

    It 'uses -ConfigPath over the environment variable' {
        $env:PSADTINTUNE_CONFIG = New-TestConfig -Path (Join-Path $TestDrive 'env.json')
        $explicit = New-TestConfig -Path (Join-Path $TestDrive 'explicit.json')

        $config = Get-PSADTIntuneConfig -ConfigPath $explicit

        $config.ConfigPath | Should -Be $explicit
        $config.ConfigSource | Should -BeLike 'Parameter*'
    }

    It 'reports a file that is not valid JSON' {
        $bad = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $bad -Value '{ not json'

        { Get-PSADTIntuneConfig -ConfigPath $bad } | Should -Throw '*could not be read as JSON*'
    }
}

Describe 'Defaults and merging' {
    BeforeEach {
        $env:APPDATA = Join-Path $TestDrive ([guid]::NewGuid())
        $env:PSADTINTUNE_CONFIG = $null
    }

    It 'returns the shipped defaults when no config file exists' {
        $config = Get-PSADTIntuneConfig

        $config.Architecture | Should -Be 'x64'
        $config.MinimumWindowsRelease | Should -Be 'W11_22H2'
        $config.ScopeTagNameArray -join ',' | Should -Be 'Default'
        $config.InstallCommandLine | Should -Be 'Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Auto'
        $config.UninstallCommandLine | Should -Be 'Invoke-AppDeployToolkit.exe -DeploymentType Uninstall -DeployMode Auto'
    }

    It 'fills settings missing from an older config file with defaults' {
        $path = Join-Path $TestDrive 'old.json'
        Set-Content -LiteralPath $path -Value "{ `"TenantId`": `"$TestTenantId`", `"AADClientId`": `"$TestClientId`" }"

        $config = Get-PSADTIntuneConfig -ConfigPath $path

        $config.TenantId | Should -Be $TestTenantId
        $config.Architecture | Should -Be 'x64'
        $config.ScopeTagNameArray -join ',' | Should -Be 'Default'
    }

    It 'treats empty values as unset' {
        $path = New-TestConfig -Path (Join-Path $TestDrive 'empty.json') -Params @{
            Architecture       = ''
            ScopeTagNameArray  = @()
            InstallCommandLine = ''
        }

        $config = Get-PSADTIntuneConfig -ConfigPath $path

        $config.Architecture | Should -Be 'x64'
        $config.ScopeTagNameArray -join ',' | Should -Be 'Default'
        $config.InstallCommandLine | Should -BeLike '*-DeploymentType Install*'
    }

    It 'keeps values from the config file over the defaults' {
        $path = New-TestConfig -Path (Join-Path $TestDrive 'custom.json') -Params @{
            Architecture      = 'arm64'
            ScopeTagNameArray = @('EMEA', 'Pilot')
            Owner             = 'IT'
        }

        $config = Get-PSADTIntuneConfig -ConfigPath $path

        $config.Architecture | Should -Be 'arm64'
        $config.ScopeTagNameArray -join ',' | Should -Be 'EMEA,Pilot'
        $config.Owner | Should -Be 'IT'
    }

    It 'does not change the shipped defaults when merging' {
        InModuleScope PSADTIntune {
            $defaults = Read-PSADTIntuneConfigFile -Path $script:DefaultConfigPath
            $override = [PSCustomObject]@{ Params = [PSCustomObject]@{ Owner = 'Changed' } }

            $merged = Merge-PSADTIntuneConfig -Base $defaults -Override $override

            $merged.Params.Owner | Should -Be 'Changed'
            $defaults.Params.Owner | Should -Be ''
        }
    }
}

Describe 'Import-PSADTIntuneConfig' {
    BeforeEach {
        $env:APPDATA = Join-Path $TestDrive ([guid]::NewGuid())
        $env:PSADTINTUNE_CONFIG = $null
    }

    It 'throws with setup instructions when no config file exists' {
        InModuleScope PSADTIntune {
            { Import-PSADTIntuneConfig } | Should -Throw '*Set-PSADTIntuneConfig*'
        }
    }

    It 'throws when TenantId and AADClientId are required but missing' {
        $path = Join-Path $TestDrive 'no-connection.json'
        Set-Content -LiteralPath $path -Value '{ "Params": { "Owner": "IT" } }'

        InModuleScope PSADTIntune -Parameters @{ Path = $path } {
            param($Path)
            { Import-PSADTIntuneConfig -ConfigPath $Path -RequireConnectionSettings } | Should -Throw '*missing: TenantId, AADClientId*'
        }
    }
}

Describe 'Set-PSADTIntuneConfig' {
    BeforeAll {
        Mock Write-Host -ModuleName PSADTIntune {}
        Mock Write-Warning -ModuleName PSADTIntune {}
        Mock Read-Host -ModuleName PSADTIntune { '' }
    }

    BeforeEach {
        $env:APPDATA = Join-Path $TestDrive ([guid]::NewGuid())
        $env:PSADTINTUNE_CONFIG = $null
        $path = Join-Path $env:APPDATA 'PSADTIntune\intune-config.json'
    }

    It 'creates the config file in the default location' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId

        $path | Should -Exist
        $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $saved.TenantId | Should -Be $TestTenantId
        $saved.AADClientId | Should -Be $TestClientId
    }

    It 'starts a new file from the template' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId

        $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $saved.Params.Architecture | Should -Be 'x64'
        $saved.Params.InstallCommandLine | Should -BeLike '*-DeploymentType Install*'
    }

    It 'changes only the settings that are passed' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId
        Set-PSADTIntuneConfig -Owner 'IT' -AADGroupId $TestGroupId

        $config = Get-PSADTIntuneConfig
        $config.TenantId | Should -Be $TestTenantId
        $config.AADClientId | Should -Be $TestClientId
        $config.Owner | Should -Be 'IT'
        $config.AADGroupId | Should -Be $TestGroupId
    }

    It 'saves a single scope tag as a JSON array' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId -ScopeTag 'Pilot'

        Get-Content -LiteralPath $path -Raw | Should -Match '"ScopeTagNameArray":\s*\[\s*"Pilot"\s*\]'
    }

    It 'clears a setting when given an empty string' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId -AADGroupId $TestGroupId
        Set-PSADTIntuneConfig -AADGroupId ''

        (Get-PSADTIntuneConfig).AADGroupId | Should -BeNullOrEmpty
    }

    It 'falls back to the default when a setting is cleared' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId -Architecture 'arm64'
        Set-PSADTIntuneConfig -Architecture ''

        (Get-PSADTIntuneConfig).Architecture | Should -Be 'x64'
    }

    It 'writes to -ConfigPath when given' {
        $custom = Join-Path $TestDrive 'custom\config.json'

        Set-PSADTIntuneConfig -ConfigPath $custom -TenantId $TestTenantId -ClientId $TestClientId

        $custom | Should -Exist
        $path | Should -Not -Exist
    }

    It 'writes nothing with -WhatIf' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId -WhatIf

        $path | Should -Not -Exist
    }

    It 'warns and leaves the file unchanged when no settings are passed' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId
        $before = Get-Content -LiteralPath $path -Raw

        Set-PSADTIntuneConfig

        Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like 'No settings specified*' }
        Get-Content -LiteralPath $path -Raw | Should -Be $before
    }

    It 'warns when TenantId or ClientId are still missing' {
        Set-PSADTIntuneConfig -Owner 'IT'

        Should -Invoke Write-Warning -ModuleName PSADTIntune -Times 1 -Exactly -ParameterFilter { $Message -like 'Still missing: TenantId, AADClientId*' }
    }

    It 'rejects a client ID that is not a GUID' {
        { Set-PSADTIntuneConfig -ClientId 'not-a-guid' } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
    }

    It 'rejects a group ID that is not a GUID' {
        { Set-PSADTIntuneConfig -AADGroupId 'Pilot Users' } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
    }

    It 'rejects an architecture that IntuneWin32App does not support' {
        { Set-PSADTIntuneConfig -Architecture 'x65' } | Should -Throw '*Valid values:*x64*'
        $path | Should -Not -Exist
    }

    It 'rejects a minimum Windows release that IntuneWin32App does not support' {
        { Set-PSADTIntuneConfig -MinimumWindowsRelease 'W12_99H9' } | Should -Throw '*Valid values:*W11_22H2*'
    }

    It 'accepts supported requirement values' {
        Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId -Architecture 'arm64' -MinimumWindowsRelease 'W10_22H2'

        $config = Get-PSADTIntuneConfig
        $config.Architecture | Should -Be 'arm64'
        $config.MinimumWindowsRelease | Should -Be 'W10_22H2'
    }

    Context 'first-time setup prompts' {
        It 'asks for TenantId and ClientId when creating a new config' {
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'TenantId*' } { 'fabrikam.onmicrosoft.com' }
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'ClientId*' } { 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' }

            Set-PSADTIntuneConfig

            $config = Get-PSADTIntuneConfig
            $config.TenantId | Should -Be 'fabrikam.onmicrosoft.com'
            $config.AADClientId | Should -Be $TestClientId
        }

        It 'does not ask when the config already exists' {
            Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId

            Set-PSADTIntuneConfig -Owner 'IT'

            Should -Invoke Read-Host -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'does not ask for values that are passed' {
            Set-PSADTIntuneConfig -TenantId $TestTenantId -ClientId $TestClientId

            Should -Invoke Read-Host -ModuleName PSADTIntune -Times 0 -Exactly
        }

        It 'rejects a prompted client ID that is not a GUID and saves nothing' {
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'TenantId*' } { 'fabrikam.onmicrosoft.com' }
            Mock Read-Host -ModuleName PSADTIntune -ParameterFilter { $Prompt -like 'ClientId*' } { 'not-a-guid' }

            { Set-PSADTIntuneConfig } | Should -Throw '*not a valid client ID*'
            $path | Should -Not -Exist
        }
    }
}
